# Cronbox README

Simple, stable, scheduled script execution.

Cron for execution, with SSH and Git for deployments.


## Description

The goal here simplicity. Someone should be able to maintain this while
understanding as few concepts as possible. Shell scripting should be enough.
Python scripting is fine. It's flexible enough to run Docker containers, but
not required.

- Local machines are too volatile.
- Lambda is painful when needing to use arbitrary CLI commands, coordinate
    Docker containers, or run something for a long time.
- ECS is overly complicated for simple scripts execution on a schedule. When a
    single file changes, the image needs to be rebuilt, deployed, etc. ECS
    configuration is more complicated. Best practice for containers is to have
    a single process, so more complexity is required for more programs.
    Having one container trigger another for concurrency is harder, unless you
    go full AWS Batch.
- EKS has the same issues as above, while also introducing a lot more
    complexity and maintenance overhead. All we want to do is execute some
    scripts on a schedule.

Instead of the above options, an EC2 Ubuntu instance is created that executes
scripts in folder at regular intervals. Done.

The bootstrapping process has some complexity to it, but none that the user
should be exposed to beyond providing AWS credentials and executing
`terraform apply`.


## Setup and Usage

1. Install `git`.
2. Install `terraform`.
3. Install the `aws` CLI and configure credentials.
4. Run `terraform apply` or `make provision`.


## Instance Provisioning and Bootstrapping

Bootstrapping happens once, when the VPS instance is first created.

EC2 instances can define a value for `user_data`, as either a shell script or a
cloud-init file, which executes during instance creation.

For a Cronbox instance, the bootstrap sequence is:
1. Terraform provisions the VPS instance, specifying a shell script as the `user_data`.
2. The shell script adds packages and sets up the instance.


## Secrets Used in Scripts

Secrets (e.g. API keys) are pulled from SSM parameter store, at the root path of
the project. For example, if the project name is `my-cronbox` then you should
store the secret at `/my-cronbox/some-api-key`.

The VPS has an IAM role that allows it to access SSM parameter store values
for the project, e.g. `/my-cronbox/*`.

The system Cron scripts call each user Cron script with `chamber`, to
automatically populate SSM Parameter Store secrets as environment varaibles.
The `chamber` CLI is installed on the host during bootstrapping.


## Deployments (SSH via EC2 Instance Connect)

The short version: `./deploy.sh` or `make deploy` (equivalent).

Ubuntu EC2 instances come with a mechanism called
[EC2 Instance Connect](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/Connect-using-EC2-Instance-Connect.html).
Temporary SSH key pairs are generated for one time use.
The Instance Connect API makes the temporary public key available to the 
instance's SSH service for 60 seconds. 
The Instance Connect API is goverened by AWS IAM policies, effectively
controlling SSH access with IAM.

> With EC2 Instance Connect, you use AWS Identity and Access Management (IAM)
> policies and principals to control SSH access to your instances, removing the
> need to share and manage SSH keys.

The `deploy.sh` script or `make deploy` command will:

1. Generate a new, short-lived, temporary SSH key pair.
2. Push the public key to the EC2 instance's metadata via Instance Connect API,
    permitted by the IAM policy.
3. Push the repo to the EC2 instance with `git push` (EC2 as the remote).

The deployment can happen from a user's local machine, a pipeline, or anywhere
that has `bash`, `git`, `ssh`, and the `aws` CLI. The `make deploy` command
is a convenience, equivalent to running the `deploy.sh` script directly.


## Cronbox Mechanics

### Repository Updates

Repositories with Cron scripts are pushed to the EC2 instance, at
`/srv/git/<repo>`. This is the "deployment" step.

At regular intervals, a script will run that clones or pulls each repository
in `/srv/git/*` to the `ubuntu` user's home directory.
During this time, a `/home/ubuntu/git/.update.<repo_name>.lock` mutex file will
be created, to prevent race conditions from other scripts executing during
repo updates.

If a repository has changes from the most recent pull, the environment will
be recreated (e.g. dependencies, Python virtual environments).


### Executing Cron Jobs

By default, Ubuntu has a few system folders for executing Cron jobs at regular
intervals.
- `/etc/cron.hourly`
- `/etc/cron.daily`
- `/etc/cron.weekly`
- `/etc/cron.monthly`

The bootstrapping process adds another system folder at `/etc/cron.5min`, that
executes scripts stored there every five minutes.

The Git repository with user scripts should contain corresponding Cron folders
for each system Cron folder.

Each system Cron folder has a script that execute each corresponding repository
Cron folder's scripts.
- `/etc/cron.5min/execute-<repo_name> --> /srv/repo/cron.5min/*`
- `/etc/cron.hourly/execute-<repo_name> --> /srv/repo/cron.hourly/*`
- `/etc/cron.daily/execute-<repo_name> --> /srv/repo/cron.daily/*`
- `/etc/cron.weekly/execute-<repo_name> --> /srv/repo/cron.weekly/*`
- `/etc/cron.monthly/execute-<repo_name> --> /srv/repo/cron.monthly/*`

The system Cron scripts call each user Cron script with `chamber`,
automatically populating SSM Parameter Store secrets as environment varaibles.

