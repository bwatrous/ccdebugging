# CCDebugging

This project is intended as a tutorial on debugging and operating Azure CycleCloud clusters.
The default software configuration contains intentional errors and missing functionality that will be patched
after the initial cluster deployment fails.

The goal of this tutorial is to modify the cluster project to correctly install both the Dask and Dask JobQueue
software on a PBSPro cluster.

We'll start from a partially completed and completely buggy CycleCloud Project, fix the bugs and finish the project.


## Prerequisites

This tutorial assumes that you have already installed and configured an Azure CycleCloud VM (version 7.7.5 or later)
in your Azure subscription.

If you have not yet configured your Azure CycleCloud VM, then you should start by creating one from the Azure
Marketplace or by following this quickstart: <https://docs.microsoft.com/en-us/azure/cyclecloud/quickstart-install-cyclecloud>.

This tutorial also assumes familiarity with CycleCloud Projects and how to deploy them.   If you have never created a CycleCloud Project, you may wish to work through this tutorial first: <https://docs.microsoft.com/en-us/azure/cyclecloud/tutorials/deploy-custom-application>

## Debugging CycleCloud Projects

### Initializing the CycleCloud CLI in CloudShell

Start by opening an [Azure CloudShell](https://docs.microsoft.com/en-us/azure/cloud-shell/overview) session from the [Azure Portal](https://portal.azure.com).   Ensure that the shell is set to Bash.

We'll use this CloudShell session for all command lines in the tutorial.

Then follow the instructions here <https://docs.microsoft.com/en-us/azure/cyclecloud/install-cyclecloud-cli> to install and then initialize the Azure CycleCloud CLI.


### Deploying the Project and Launching the initial cluster


We're going to start by cloning the project from GitHub:

``` bash

  mkdir -p ~/tutorial
  cd ~/tutorial
  git clone https://github.com/bwatrous/ccdebugging.git


Next, let's deploy the current project to your Azure CycleCloud locker (referred to as "azure-storage" for the rest of
this tutorial):

``` bash
  cd ~/tutorial/ccdebugging
  cyclecloud project upload azure-storage


Assuming that CycleCloud is running and reachable, the upload should report 100% completed.



```
  **IMPORTANT**
  - Before starting the cluster at the end of this section, verify that you have added your SSH public key to your
    CycleCloud user's Profile.
    

Next, let's import the tutorial cluster template to CycleCloud as a new cluster type:

``` bash
  cd ~/tutorial/ccdebugging
  cyclecloud import_template CCDebugging -f ./templates/ccdebugging.txt


Finally, let's create a cluster using the new cluster creation icon we just created:

  1. Open a browser tab to your Azure CycleCloud UI
  2. From the "Clusters" page, click the "**+**" button at the bottom of the "Clusters" frame
  3. From the "Cluster Creation" page,
     a. Click on the new "CCDebugging" icon to create a new CCDebugging cluster
     b. Give the cluster a name (the tutorial uses "ccdebuggingTest"), then click "Next"
     c. On the "Required Settings" page:
        i. Select SKU types for both Master and Execute nodes for which you have quota
	ii. Select the proper subnet for the test cluster
	111. If no public IP is required/desired, then uncheck the "Return Proxy" and "Public Head Node" boxes.
	iv. Click "Save"

  4. On the new cluster page, click "Start" to launch the cluster


### Identifying the errors

Wait for the cluster to start.   You should see the "master" node go to the "Awaiting software installation..." state, and then "Node software installation failure, retrying..." state (and if you wait long enough it will change from blue to red when the software installation retries run out).


Now, we just have to figure out what went wrong...
Connect to the cluster using SSH or using the CycleCloud CLI's "connect" command.

``` bash
  $ cyclecloud connect -c ccdebuggingTest master
  Connecting to admin@52.247.222.206 (ccdebuggingTest master) using SSH
  Warning: Permanently added '52.247.222.206' (ECDSA) to the list of known hosts.

   __        __  |    ___       __  |    __         __|
  (___ (__| (___ |_, (__/_     (___ |_, (__) (__(_ (__|
	  |

  Cluster: ccdebuggingTest
  Version: 7.8.0
  Run List: recipe[cyclecloud], recipe[anaconda], role[pbspro_master_role], recipe[cluster_init]
  [admin@ip-0A800009 ~]$ 


The first place to look when debugging a CycleCloud cluster is the `chef-client.log` in  Jetpack logs directory.  Use the `tail -f ./chef-client.log` to follow the converge process, or simply open the file in `less` and search for "**ERROR**":

``` bash
  [admin@ip-0A800009 ~]$ sudo -i
  [root@ip-0A800009 ~]# cd /opt/cycle/jetpack/logs/
  [root@ip-0A800009 logs]# tail -f chef-client.log


At the end of the log, you should see something like this:

``` bash
  [2019-07-23T07:31:19+00:00] ERROR: Running exception handlers
  [2019-07-23T07:31:20+00:00] INFO: Posted converge history report
  [2019-07-23T07:31:20+00:00] ERROR: Exception handlers complete
  **[2019-07-23T07:31:20+00:00] FATAL: Stacktrace dumped to /opt/cycle/jetpack/system/chef/cache/chef-stacktrace.out**
  [2019-07-23T07:31:20+00:00] FATAL: Please provide the contents of the stacktrace.out file if you file a bug report
  [2019-07-23T07:31:20+00:00] ERROR: Chef::Exceptions::MultipleFailures
  [2019-07-23T07:31:20+00:00] FATAL: Chef::Exceptions::ChildConvergeError: Chef run process exited unsuccessfully (exit code 1)


That error message wasn't super helpful.  But...   It did tell you where to go next: 
**FATAL: Stacktrace dumped to /opt/cycle/jetpack/system/chef/cache/chef-stacktrace.out**

(Note: If one of the chef recipes had failed, then there might be enough information here in the `chef-client.log` to diagnose the issue.)


If you open `/opt/cycle/jetpack/system/chef/cache/chef-stacktrace.out` and search for the word "Error", you'll see
a section like this:

``` bash
  Script 100_create_anaconda_environments.sh has already run successfully, skipping
  Script 10_setup_condarc.sh has already run successfully, skipping
  Script 50_install_packages.sh has already run successfully, skipping
  Running cluster-init scripts for project 'ccdebugging v1.0.0' spec 'default'
  **Executing cluster-init script: /mnt/cluster-init/ccdebugging/default/scripts/010_create_conda_env.sh, output written to /opt/cycle/jetpack/logs/cluster-init/ccdebugging/default/scripts/010_create_conda_env.sh.out**
  **Failed to execute cluster-init script '/mnt/cluster-init/ccdebugging/default/scripts/010_create_conda_env.sh' (1)**
  Error:


Surprisingly, it looks like one of the cluster-init scripts from our intentionally broken projects has failed:
**Failed to execute cluster-init script '/mnt/cluster-init/ccdebugging/default/scripts/010_create_conda_env.sh' (1)**


Directly above that line, we see the paths to both the executing script and the log of stderr and stdout for the script:
**Executing cluster-init script: /mnt/cluster-init/ccdebugging/default/scripts/010_create_conda_env.sh, output written to /opt/cycle/jetpack/logs/cluster-init/ccdebugging/default/scripts/010_create_conda_env.sh.out**


If you open the cluster-init log: `/opt/cycle/jetpack/logs/cluster-init/ccdebugging/default/scripts/010_create_conda_env.sh.out`, you'll find an error like this:

``` bash
  + set -e
  + conda update -n base -c defaults conda
  Collecting package metadata (current_repodata.json): ...working... failed

  UnavailableInvalidChannel: The channel is not accessible or is invalid.
    channel name: idontexist
    channel url: https://conda.anaconda.org/idontexist
    error code: 404

  You will need to adjust your conda configuration to proceed.
  Use `conda config --show channels` to view your configuration's current state,
  and use `conda config --show-sources` to view config file locations.


The Conda channel "idontexist" is not acccessible or invalid.


### Applying software changes to the live cluster

Now that we know what's wrong with our cluster, we just need to fix the problem...
There's no need to terminate and wait for restart.   We'll patch the cluster-init and verify it live.

Exit the SSH session on the master.

Currently, there's only one custom configuration script in the project:
`specs/default/cluster-init/scripts/010_create_conda_env.sh`

So go back to your project directory and edit that file, and remove the following line:
`conda config --add channels idontexist`

Save the modified script, and re-upload the project:

``` bash
  cd ~/tutorial/ccdebugging
  vi specs/default/cluster-init/scripts/010_create_conda_env.sh
  cyclecloud project upload azure-storage


Now, re-connect to the master node and tail the `chef-client.log` again:

``` bash
  [admin@ip-0A800009 ~]$ sudo -i
  [root@ip-0A800009 ~]# cd /opt/cycle/jetpack/logs/
  [root@ip-0A800009 logs]# tail -f chef-client.log


It may take a few minutes...   And then you'll see the converge fail again.
Looking at the log `/opt/cycle/jetpack/logs/cluster-init/ccdebugging/default/scripts/010_create_conda_env.sh.out` again, you'll see that the error message is unchanged.  That's because adding the conda channel was persistent.
Let's try removing the bad channel:

``` bash
  [root@ip-0A800009 logs]# conda config --show channels
  channels:
    - defaults
    - conda-forge
    - idontexist
    - bioconda
    - r
  [root@ip-0A800009 logs]# conda config --remove idontexist

Now tail the `chef-client.log` again.  This time, you should see the converge end with the line:
** INFO: Report handlers complete **




### Opening access to the Dask UI

Somne changes cannot be made automatically to a live cluster with a terminate and restart.  If the changes only apply to the worker/execute nodes, that's generally not a problem - just terminate the workers and let the autoscaler replace them when jobs enter the queue.   If the changes affect non-autoscaling VMs, then the recommended approach for these changes is (if possible) to apply them manually to the affected VMs and then update the cluster template so they will be re-applied for future restarts.


As an example of this type of change...
Dask provides a UI for monitoring jobs, but it's on a port that is not opened in our Network Security Group.
If we want to open that port, then we should do it on the live cluster (without a restart) but we should also update
the cluster template, the cluster creation UI, and the running cluster's definition so that next time we terminate
and restart or create a new cluster, the change has already been applied.

``` bash
  **NOTE**
  - Generally, cluster policy changes such as MaxCoreCount, and purely additive changes to software configuration (that do not require cluster template/parameter changes) may be made without restart.
  - Software configuration changes to running VMs generally require manual intervention to apply the change live, or a node terminate and restart.
  - Changes to the VM infrastructure generally require a node or cluster terminate and restart.


First, let's make sure that opening the port works on the running cluster.
Navigate to the Master node in the Azure Portal by:

  1. Select the Master node in the CycleCloud cluster "Nodes Table"
  2. In the bottom half of the split table, double click on the "master" row
  3. In the pop-up "Node Details" dialog, click the "View in Portal: Virtual machine" link
  4. Select the "Networking" blade
  5. Open port **8787**

Then next time you submit a dask job, you should now be able to open the Dask UI in a browser tab using the Master node's with URL:
http://<master_ip>:8787


Now, let's ensure that the next time we restart or create a new cluster, the port is opened automatically.

First, add the following to the `[[node master]]` section of `./templates/ccdebugging.txt`:

``` bash
        [[[input-endpoint dask]]]
        PrivatePort = 8787
        PublicPort = 8787


Next, re-import the cluster template to apply the change to the cluster creation UI:

``` bash
  cyclecloud import_template CCDebugging -f ./templates/ccdebugging.txt --force


(Note: that we need to add `--force` to over-write the existing creation form.)


Finally, let's update our running cluster so that it will be open on the next cluster terminate and restart.
To do that:

  1. Export the current cluster parameters to file
  2. Ensure that the changes are applied to the cluster template
  3. Import the cluster with `--force` option (to apply changes to an existing cluster)

``` bash
    cyclecloud export_parameters ccdebuggingTest > ccdebuggingTest.json
    vi ./templates/ccdebugging.txt
    cyclecloud import_cluster ccdebuggingTest -c CCDebugging -f ./templates/ccdebugging.txt -p ccdebuggingTest.json --force




### Bonus: Let's add a unit test!






