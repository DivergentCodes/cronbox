#!/bin/bash

###############################################################################
# Bootstrap an Ubuntu cronbox VPS. Runs once on instance creation.
#
# - Installs Chamber
# - Installs Docker
# - Creates a simple Git server that auto-inits bare repos on push.
#
###############################################################################


# https://github.com/segmentio/chamber/releases
CHAMBER_VERSION="v2.11.0"


GIT_SSH_WRAPPER_PATH="/usr/local/bin/git-ssh-wrapper"


upgrade_packages() {
  apt-get update -y;
  apt-get upgrade -y;
}


install_base_packages() {
  apt-get install -y \
    build-essentials \
    software-properties-common \
    unattended-upgrades \
    ;
}


install_chamber() {
  chamber_version="${CHAMBER_VERSION}"
  chamber_file="/usr/local/bin/chamber-${chamber_version}"

  curl \
    --location \
    --silent \
    -o "${chamber_file}" \
    "https://github.com/segmentio/chamber/releases/download/${chamber_version}/chamber-${chamber_version}-linux-amd64"

  chmod 755 "${chamber_file}"

  ln -s "${chamber_file}" "/usr/local/bin/chamber"
}


install_docker() {
	# https://docs.docker.com/engine/install/ubuntu/

	# Add the Docker APT repository.
	apt-get update;
	apt-get install -y \
		ca-certificates \
		curl \
		gnupg \
		lsb-release \
    ;

	mkdir -p /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
		| gpg --dearmor -o /etc/apt/keyrings/docker.gpg;

	echo \
		"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
		$(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null;

  # Install Docker packages.
  apt-get update -y;
	apt install -y \
		docker-ce  \
		docker-ce-cli  \
		containerd.io  \
		docker-compose-plugin \
    ;

  # Add regular user to Docker group.
  usermod -a -G docker ubuntu
}


# The user-data.sh script must be entirely standalone.
# Define an inline script that will be dropped on the host.
generate_git_ssh_wrapper() {
cat > "$GIT_SSH_WRAPPER_PATH" << EOF
#!/bin/bash

# Triggered by sshd_config's ForceCommand option.
# Executes when the configured user SSH's into the server.
# Used to automatically create a bare Git repo on push.
#
# The script executes as the SSH user.
#
# Command issued by user: git push
# Command sent over SSH:  git-receive-pack '/srv/git/myrepo.git'

GIT_USER="git"
GIT_BASE_PATH="/srv/git/"

# Command present. Ensure it is a valid git push.
if [[ -n \$SSH_ORIGINAL_COMMAND ]]; then

    # Parse the original SSH command into what is expected.
    repo_cmd="\$(echo \$SSH_ORIGINAL_COMMAND | awk '{print \$1}')"
    repo_path=\$(echo \$SSH_ORIGINAL_COMMAND | awk '{print \$2}' | sed "s/'//g")

    # Fail if wrong command (not from git push).
    if [[ "\$repo_cmd" != "git-receive-pack" ]]; then
        >&2 echo "Git SSH custom error: command [\$repo_cmd] not git-receive-pack (from git push)";
        exit 1;
    fi

    # Fail if path does not begin with base repo path.
    if [[ "\$repo_path" != \$GIT_BASE_PATH* ]]; then
        >&2 echo "Git SSH custom error: path [\$repo_path] is not with Git base path \$GIT_BASE_PATH";
        exit 1;
    fi

    # Initialize bare Git repo if it doesn't exist.
    if [[ ! -f "\$repo_path" ]]; then
        # Output sent to /dev/null, otherwise the push returns an error.
        # fatal: protocol error: bad line length character: Init
        git --bare init \$repo_path > /dev/null
    fi

    # Perform the original git push.
    eval \$SSH_ORIGINAL_COMMAND

# No command. Let user know account is valid.
else
    exec bash -il
fi
EOF
  chmod 755 "$GIT_SSH_WRAPPER_PATH";
}


configure_sshd_git_user() {
cat >> "/etc/ssh/sshd_config" << EOF

Match User git
        X11Forwarding no
        AllowTcpForwarding no
        ForceCommand $GIT_SSH_WRAPPER_PATH

EOF

  systemctl restart sshd
}


configure_git_server() {
  useradd git

  # Default branch is always main for all users.
  git config --global init.defaultBranch "main"
  sudo -u "ubuntu" git config --global init.defaultBranch "main"
  sudo -u "git" git config --global init.defaultBranch "main"

  # Create the base Git repo path.
  mkdir -p /srv/git
  chown -R git:git /srv/git

  # Create wrapper for git user that allows automatic bare repo creation on
  # push, and restricts allowed SSH commands for the git user.
  generate_git_ssh_wrapper;
  configure_sshd_git_user;
}


upgrade_packages;
install_base_packages;
install_chamber;
install_docker;
configure_git_server;
