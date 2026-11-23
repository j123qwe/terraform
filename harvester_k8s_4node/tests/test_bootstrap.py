import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class BootstrapTests(unittest.TestCase):
    def test_application_providers_wait_for_stable_kubeconfig(self):
        graph = subprocess.run(
            ["terraform", f"-chdir={ROOT}", "graph", "-type=plan"],
            text=True,
            capture_output=True,
            check=True,
        ).stdout
        ready = '"[root] terraform_data.kubeconfig_ready (expand)"'
        cluster = '"[root] terraform_data.cluster_config (expand)"'
        self.assertIn(f"{ready} -> {cluster}", graph)
        for provider in ("helm", "kubernetes"):
            alias = ".cluster" if provider == "kubernetes" else ""
            provider_node = f'"[root] provider[\\"registry.terraform.io/hashicorp/{provider}\\"]{alias}"'
            self.assertIn(f"{provider_node} -> {ready}", graph)

    def render_installer(self, server):
        args = {
            "node_name": "test-node",
            "is_server": server,
            "rke2_version": "v1.37.1+rke2r1",
            "config": '{"token":"test-only"}',
            "cilium_config": '{"kind":"HelmChartConfig"}',
        }
        expression = (
            "jsonencode(templatefile("
            + json.dumps(str(ROOT / "templates/install-rke2.sh.tftpl"))
            + ", "
            + json.dumps(args)
            + "))"
        )
        result = subprocess.run(
            ["terraform", f"-chdir={ROOT / 'tests'}", "console", "-no-color"],
            input=expression,
            text=True,
            capture_output=True,
            check=True,
        )
        return json.loads(json.loads(result.stdout))

    def test_installer_templates_render_for_server_and_agent(self):
        for server in (True, False):
            with self.subTest(server=server):
                script = self.render_installer(server)
                subprocess.run(["bash", "-n"], input=script, text=True, check=True)
                self.assertEqual("CILIUM" in script, server)
                self.assertIn("cloud-init status --wait", script)
                self.assertIn(f"INSTALL_RKE2_TYPE='{'server' if server else 'agent'}'", script)

    def test_service_start_waits_for_recovery_and_reports_timeout(self):
        script = self.render_installer(False)
        function = "start_rke2() {" + script.split("start_rke2() {", 1)[1].split("\n}\n", 1)[0] + "\n}\n"
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            systemctl = directory / "systemctl"
            systemctl.write_text(
                "#!/usr/bin/env bash\n"
                'printf "%s\\n" "$*" >> "$TEST_LOG"\n'
                'if [[ "$1" == is-active ]]; then\n'
                '  count=0; [[ ! -f "$TEST_COUNT" ]] || read -r count < "$TEST_COUNT"\n'
                '  count=$((count + 1)); echo "$count" > "$TEST_COUNT"\n'
                '  (( count >= TEST_READY_AFTER )) || exit 3\n'
                "fi\n"
            )
            (directory / "sleep").write_text("#!/usr/bin/env bash\nexit 0\n")
            (directory / "journalctl").write_text("#!/usr/bin/env bash\necho 'simulated registry failure'\n")
            for name in ("systemctl", "sleep", "journalctl"):
                (directory / name).chmod(0o700)

            for ready_after, expected in ((3, 0), (999, 1)):
                with self.subTest(ready_after=ready_after):
                    count = directory / "count"
                    log = directory / "log"
                    count.unlink(missing_ok=True)
                    log.unlink(missing_ok=True)
                    result = subprocess.run(
                        ["bash", "-euo", "pipefail", "-c", function + "start_rke2 rke2-agent"],
                        env={
                            **os.environ,
                            "PATH": f"{directory}:{os.environ['PATH']}",
                            "TEST_LOG": str(log),
                            "TEST_COUNT": str(count),
                            "TEST_READY_AFTER": str(ready_after),
                        },
                        text=True,
                        capture_output=True,
                        timeout=10,
                    )
                    self.assertEqual(result.returncode, expected, result.stderr)
                    self.assertIn("start --no-block rke2-agent", log.read_text())
                    if expected:
                        self.assertIn("did not become active", result.stderr)
                        self.assertIn("simulated registry failure", result.stderr)
                    else:
                        self.assertEqual(count.read_text().strip(), "3")

    def run_helper(self, mode, install_exit=0, apply_exit=0, node_count=4,
                   interface="enp1s0", worker2_interface=None, detect=True,
                   verify_host_keys=False):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        directory = Path(temporary.name)
        log = directory / "commands"
        ssh = directory / "ssh"
        ssh.write_text(
            "#!/usr/bin/env bash\n"
            'printf "ssh %s\\n" "$*" >> "$TEST_LOG"\n'
            'case "$*" in\n'
            '  *" true") exit 0 ;;\n'
            '  *"sudo -A bash -s") cat > "$TEST_INPUT"; exit "$TEST_INSTALL_EXIT" ;;\n'
            '  *"ip -o -4 addr show to"*)\n'
            '    iface="$TEST_INTERFACE"\n'
            '    [[ "$*" != *"ubuntu@192.0.2.12"* ]] || iface="$TEST_WORKER2_INTERFACE"\n'
            '    [[ -z "$iface" ]] || printf "2: %s inet 192.0.2.11/24\\n" "$iface" ;;\n'
            "  *) printf 'clusters:\\n- cluster:\\n    server: https://127.0.0.1:6443\\n' ;;\n"
            "esac\n"
        )
        kubectl = directory / "kubectl"
        kubectl.write_text(
            "#!/usr/bin/env bash\n"
            'printf "kubectl %s\\n" "$*" >> "$TEST_LOG"\n'
            'if [[ "$*" == "get nodes -o name" ]]; then\n'
            '  for ((i=0;i<TEST_NODE_COUNT;i++)); do echo node/test-$i; done\n'
            'elif [[ "$*" == "apply -f "* ]]; then\n'
            '  cat "$3" > "$TEST_APPLIED"\n'
            '  exit "$TEST_APPLY_EXIT"\n'
            "fi\n"
        )
        sleep = directory / "sleep"
        sleep.write_text("#!/usr/bin/env bash\nexit 0\n")
        for executable in (ssh, kubectl, sleep):
            executable.chmod(0o700)
        key = directory / "key"
        key.write_text("test-only")
        installer = directory / "install.sh"
        installer.write_text("echo test-install\n")
        manifest = directory / "manifest.yaml"
        manifest.write_text('interfaces: ["__DETECT_PRIMARY_INTERFACE__"]\n')
        config = directory / "kubeconfig.yaml"
        environment = {
            **os.environ,
            "PATH": f"{directory}:{os.environ['PATH']}",
            "NODE_IP": "192.0.2.10",
            "SSH_USER": "ubuntu",
            "SSH_KEY": str(key),
            "VERIFY_SSH_HOST_KEYS": "true" if verify_host_keys else "false",
            "KNOWN_HOSTS": str(directory / "known_hosts"),
            "INSTALL_FILE": str(installer),
            "MANIFEST_FILE": str(manifest),
            "KUBECONFIG": str(config),
            "DETECT_L2": "true" if detect else "false",
            "WORKER_NAMES": "k8s-worker-1 k8s-worker-2 k8s-worker-3",
            "WORKER_IPS": "192.0.2.11 192.0.2.12 192.0.2.13",
            "BOOTSTRAP_DIR": str(directory),
            "TEST_LOG": str(log),
            "TEST_APPLIED": str(directory / "applied"),
            "TEST_INPUT": str(directory / "uploaded"),
            "TEST_INSTALL_EXIT": str(install_exit),
            "TEST_APPLY_EXIT": str(apply_exit),
            "TEST_NODE_COUNT": str(node_count),
            "TEST_INTERFACE": interface,
            "TEST_WORKER2_INTERFACE": interface if worker2_interface is None else worker2_interface,
        }
        result = subprocess.run(
            ["bash", str(ROOT / "scripts/cluster.sh"), mode],
            env=environment,
            text=True,
            capture_output=True,
            timeout=10,
        )
        return result, directory, log, config

    def test_install_uses_sudo_and_propagates_failures(self):
        result, directory, log, _ = self.run_helper("install")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((directory / "uploaded").read_text(), "echo test-install\n")
        self.assertIn("StrictHostKeyChecking=no", log.read_text())
        self.assertIn("UserKnownHostsFile=/dev/null", log.read_text())
        self.assertIn("GlobalKnownHostsFile=/dev/null", log.read_text())
        self.assertIn("sudo -A bash -s", log.read_text())
        result, _, _, _ = self.run_helper("install", install_exit=1)
        self.assertNotEqual(result.returncode, 0)

    def test_configure_waits_and_applies_resources(self):
        result, directory, log, config = self.run_helper("configure")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("https://192.0.2.10:6443", config.read_text())
        self.assertEqual(stat.S_IMODE(config.stat().st_mode), 0o600)
        commands = log.read_text()
        self.assertIn("wait --for=condition=Ready nodes --all", commands)
        self.assertIn("crd/ciliumloadbalancerippools.cilium.io", commands)
        self.assertIn("crd/ciliuml2announcementpolicies.cilium.io", commands)
        self.assertIn("rollout status deployment/cilium-operator", commands)
        self.assertIn("apply -f", commands)
        self.assertIn("cilium.io/PoolConflict", commands)
        self.assertIn('interfaces: ["^enp1s0$"]', (directory / "applied").read_text())
        ssh_commands = [line for line in commands.splitlines() if line.startswith("ssh ")]
        self.assertEqual(len(ssh_commands), 5)
        self.assertTrue(all("StrictHostKeyChecking=no" in line and "UserKnownHostsFile=/dev/null" in line and "GlobalKnownHostsFile=/dev/null" in line for line in ssh_commands))

    def test_optional_host_key_verification(self):
        result, directory, log, _ = self.run_helper("configure", verify_host_keys=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        ssh_commands = [line for line in log.read_text().splitlines() if line.startswith("ssh ")]
        self.assertTrue(all("StrictHostKeyChecking=accept-new" in line and "/dev/null" not in line for line in ssh_commands))
        self.assertIn(f"UserKnownHostsFile={directory / 'known_hosts-k8s-worker-1'}", log.read_text())

    def test_detected_interface_is_literal_and_worker_mismatches_fail(self):
        result, directory, _, _ = self.run_helper("configure", interface="enp1s0.100")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('interfaces: ["^enp1s0[.]100$"]', (directory / "applied").read_text())
        result, _, log, _ = self.run_helper("configure", worker2_interface="ens4")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("different primary interface names", result.stderr)
        self.assertNotIn("apply -f", log.read_text())
        result, _, _, _ = self.run_helper("configure", worker2_interface="")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Could not identify one primary interface", result.stderr)

    def test_override_skips_detection(self):
        result, directory, log, _ = self.run_helper("configure", detect=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("ip -o -4 addr show", log.read_text())
        self.assertEqual((directory / "applied").read_text(), 'interfaces: ["__DETECT_PRIMARY_INTERFACE__"]\n')

    def test_configure_propagates_failure_and_requires_all_nodes(self):
        result, _, _, _ = self.run_helper("configure", apply_exit=1)
        self.assertNotEqual(result.returncode, 0)
        result, _, log, _ = self.run_helper("configure", node_count=3)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Expected four registered nodes", result.stderr)
        self.assertNotIn("apply -f", log.read_text())


if __name__ == "__main__":
    unittest.main()
