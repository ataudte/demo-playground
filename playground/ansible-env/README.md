# ansible-env

A reusable launcher for Ansible projects. It uses an existing Python installation, creates or reuses a project-local virtual environment, installs missing dependencies and opens an activated shell.

Each project has its own `.venv`. Ansible runs on demand; no background service is required.

## Prerequisites

- Python 3.12, 3.13 or 3.14
- Bash on a Unix-like control node
- Internet access when packages need to be downloaded

The base runtime is pinned to `ansible-core 2.20.11`. The launcher does not download another Python interpreter.

## Getting started

Open a terminal in the extracted `ansible-env` directory:

```bash
chmod +x ./ansible-env
export PATH="$PWD:$PATH"
```

The PATH setting applies to the current terminal session. For later sessions, add the tool’s absolute directory to the shell configuration or invoke it using its full path.

## Test the installation

### 1. Run the local Ansible check

Create a test project and run the built-in check:

```bash
mkdir -p "$HOME/ansible-test"
ansible-env check --project "$HOME/ansible-test"
```

The launcher automatically creates the environment if necessary, installs the required packages and executes Ansible’s ping module locally.

Successful output includes:

```text
localhost | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

This confirms that Ansible can execute a Python module through the project environment.

### 2. Test automatic activation

Start the prepared shell:

```bash
ansible-env start --project "$HOME/ansible-test"
```

The prompt should begin with `(ansible)`, for example:

```text
(ansible) ansible-test $
```

Inside that shell, run:

```bash
ansible --version
python -c 'import sys; print(sys.prefix)'
```

Expected results:

- Ansible reports core version `2.20.11`.
- The Python environment path ends with `ansible-test/.venv`.

No separate activation command is needed.

### 3. Stop and restart

Leave the prepared shell:

```bash
stop
```

Alternatively, use `exit` or press Ctrl+D.

Start it again:

```bash
ansible-env start --project "$HOME/ansible-test"
```

The existing environment and compatible packages are reused. Type `stop` again when finished.

### 4. Optional: test missing-package recovery

The following deliberately removes Jinja2 from the test project’s environment:

```bash
ansible-env exec --project "$HOME/ansible-test" -- python -m pip uninstall -y Jinja2
```

Run setup again:

```bash
ansible-env setup --project "$HOME/ansible-test"
```

The launcher should detect the missing dependency and reinstall the required version.

Confirm that Ansible works again:

```bash
ansible-env check --project "$HOME/ansible-test"
```

The result should again contain `"ping": "pong"`.

## Use with an Ansible project

From an existing project directory:

```bash
ansible-env start
```

Or select the directory explicitly:

```bash
ansible-env start --project /path/to/project
```

To include additional project dependencies:

```bash
ansible-env start --project /path/to/project --requirements requirements.txt
```

The requirements path is relative to the selected project. Product SDKs and other project-specific Python packages belong in that requirements file.

## Commands

| Action | Command |
| --- | --- |
| Start an activated shell | `ansible-env start` |
| Leave the prepared shell | `stop` or `exit` |
| Check and install required packages | `ansible-env setup` |
| Run the local Ansible check | `ansible-env check` |
| Inspect the runtime without installing packages | `ansible-env status` |
| Run a command in the environment | `ansible-env exec -- ansible-playbook playbooks/main.yml` |
| Reinstall damaged packages | `ansible-env repair` |

Commands accept `--project DIR` and, where applicable, `--requirements FILE`. The current directory is the default project.

Ctrl+C cancels a running foreground command. Leaving the shell retains the environment and does not undo changes made by playbooks.

## Select an existing Python interpreter

If `python3` does not point to a compatible interpreter, select an installed executable when creating the environment:

```bash
ANSIBLE_ENV_PYTHON=/path/to/python3.12 ansible-env start --project /path/to/project
```

An existing `.venv` is reused.

## How dependency checks work

Before opening the shell or executing a command, the launcher:

1. Creates `.venv` if it is missing.
2. Checks the Python version.
3. Checks the base and selected project requirements.
4. Installs missing or mismatched packages.
5. Makes the environment available to the requested shell or command.

Compatible installed packages are reused. Advanced pip requirement syntax is delegated to pip.

When present, the selected project’s `ansible.cfg` is used. Otherwise, Ansible’s normal configuration discovery applies.

## Troubleshooting

**`ansible-env: command not found`**

Repeat the PATH setting from the tool directory, or use its full path:

```bash
bash /path/to/ansible-env/ansible-env check --project "$HOME/ansible-test"
```

**Unsupported Python version**

Select an existing Python 3.12–3.14 interpreter using `ANSIBLE_ENV_PYTHON`.

**Dependency installation fails**

Check the reported pip error and the selected requirements file. Conflicting requirements must be resolved before startup can complete.

**Package files appear damaged**

Run:

```bash
ansible-env repair --project /path/to/project
```