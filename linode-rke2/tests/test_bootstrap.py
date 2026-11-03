import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class BootstrapTests(unittest.TestCase):
    def test_rendered_install_scripts(self):
        for server, seed in [(True, True), (True, False), (False, False)]:
            with self.subTest(server=server, seed=seed):
                parameters = {
                    "node_name": "test-node",
                    "is_server": server,
                    "is_seed": seed,
                    "rke2_version": "v1.37.1+rke2r1",
                    "config": '{"token":"test-only","node-name":"test-node"}',
                    "cilium_config": '{"kind":"HelmChartConfig"}',
                    "ccm_config": (ROOT / "templates/linode-ccm-config.yaml").read_text(),
                    "cloud_manifests": '{"kind":"Secret"}',
                }
                expression = (
                    "jsonencode(templatefile("
                    + json.dumps(str(ROOT / "templates/install-rke2.sh.tftpl"))
                    + ", "
                    + json.dumps(parameters)
                    + "))"
                )
                result = subprocess.run(
                    ["terraform", f"-chdir={ROOT / 'tests'}", "console", "-no-color"],
                    input=expression,
                    text=True,
                    capture_output=True,
                    check=True,
                )
                script = json.loads(json.loads(result.stdout))
                subprocess.run(["bash", "-n"], input=script, text=True, check=True)
                self.assertEqual("LINODE_CLOUD" in script, seed)
                self.assertEqual("CILIUM" in script, server)
                self.assertEqual("LINODE_CCM_CONFIG" in script, seed)
                self.assertIn(
                    f"INSTALL_RKE2_TYPE='{'server' if server else 'agent'}'", script
                )
                self.assertNotIn("%{", script)

    def run_helper(
        self, mode, ssh_failure=False, uninitialized=False, storage_default="true|Delete"
    ):
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
            '  *" bash -s") cat > "$TEST_INPUT"; exit "$TEST_INSTALL_EXIT" ;;\n'
            "  *) printf 'clusters:\\n- cluster:\\n    server: https://127.0.0.1:6443\\n' ;;\n"
            "esac\n"
        )
        kubectl = directory / "kubectl"
        kubectl.write_text(
            "#!/usr/bin/env bash\n"
            'printf "kubectl %s\\n" "$*" >> "$TEST_LOG"\n'
            'if [[ "$*" == "get nodes -o name" ]]; then\n'
            "  printf 'node/master\\nnode/worker1\\nnode/worker2\\nnode/worker3\\n'\n"
            'elif [[ "$*" == "get storageclass linode-block-storage"* ]]; then\n'
            '  printf "%s" "$TEST_STORAGE_DEFAULT"\n'
            'elif [[ "$*" == *"jsonpath="* && "$TEST_UNINITIALIZED" == true ]]; then\n'
            "  echo node.cloudprovider.kubernetes.io/uninitialized\n"
            "fi\n"
        )
        ssh.chmod(0o700)
        kubectl.chmod(0o700)
        sleep = directory / "sleep"
        sleep.write_text("#!/usr/bin/env bash\nexit 0\n")
        sleep.chmod(0o700)
        key = directory / "test-key"
        key.write_text("test-only-placeholder")
        install = directory / "install.sh"
        install.write_text("echo test-install\n")
        config = directory / "kubeconfig.yaml"
        environment = {
            **os.environ,
            "PATH": f"{directory}:{os.environ['PATH']}",
            "NODE_IP": "203.0.113.10",
            "SSH_KEY": str(key),
            "KNOWN_HOSTS": str(directory / "known_hosts"),
            "INSTALL_FILE": str(install),
            "KUBECONFIG": str(config),
            "API_URL": "https://203.0.113.20:6443",
            "EXPECTED_NODES": "4",
            "TEST_LOG": str(log),
            "TEST_INPUT": str(directory / "uploaded"),
            "TEST_INSTALL_EXIT": "1" if ssh_failure else "0",
            "TEST_UNINITIALIZED": "true" if uninitialized else "false",
            "TEST_STORAGE_DEFAULT": storage_default,
        }
        result = subprocess.run(
            ["bash", str(ROOT / "scripts/cluster.sh"), mode],
            env=environment,
            text=True,
            capture_output=True,
            timeout=10,
        )
        return result, directory, log, config

    def test_upload_preserves_host_key_checks_and_stdin(self):
        result, directory, log, _ = self.run_helper("install")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((directory / "uploaded").read_text(), "echo test-install\n")
        self.assertIn("StrictHostKeyChecking=accept-new", log.read_text())
        self.assertIn("IdentitiesOnly=yes", log.read_text())

    def test_installer_failure_is_not_suppressed(self):
        result, _, _, _ = self.run_helper("install", ssh_failure=True)
        self.assertNotEqual(result.returncode, 0)

    def test_kubeconfig_endpoint_permissions_and_readiness(self):
        result, _, log, config = self.run_helper("kubeconfig")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("https://203.0.113.20:6443", config.read_text())
        self.assertNotIn("127.0.0.1", config.read_text())
        self.assertEqual(stat.S_IMODE(config.stat().st_mode), 0o600)
        commands = log.read_text()
        self.assertIn("wait --for=condition=Ready nodes --all", commands)
        self.assertIn("rollout status statefulset/csi-linode-controller", commands)
        self.assertIn("rollout status daemonset/rke2-multus", commands)
        self.assertIn("rollout status daemonset -n kube-system", commands)

    def test_uninitialized_cloud_nodes_fail_readiness(self):
        result, _, _, _ = self.run_helper("kubeconfig", uninitialized=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("CCM has not initialized all nodes", result.stderr)

    def test_wrong_default_storage_class_fails_readiness(self):
        result, _, _, _ = self.run_helper("kubeconfig", storage_default="false|Retain")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("default class with Delete reclaim policy", result.stderr)


if __name__ == "__main__":
    unittest.main()
