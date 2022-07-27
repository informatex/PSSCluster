# PSSCluster

This powershell module is used to configure and manage high available powershell script over a windows server failover cluster using git repositories. It use the windows built-in failover technologie to provide high available script failover between cluster nodes.


## Features

 - Use git repositories as script integrity and replication.
 - Can use existing cluster to transform local powershell script into a failover environment.
 - Free.
 - No 3-party software to install.
 - Community based.
 - Active/Active mode.
 - Active/Passive mode.
 - PSSCluster is logging event into the event viewer.
 - Template wrapping script is automatically created with new repositories.
 - Template scheduled task is automatically created with new repositories.
 - Automatically put uncompliant nodes in maintenance mode.

## Prerequisites

 - Windows Git x64 must be installed on each nodes.
 https://git-scm.com/download/win
 - Windows Failover Cluster must be configures prior to configure PSSCluster.
 https://docs.microsoft.com/en-us/windows-server/failover-clustering/failover-clustering-overview
 - Failover Cluster Quorum should be configured.
 https://docs.microsoft.com/en-us/windows-server/failover-clustering/manage-cluster-quorum

## Restrictions

 - You can use this module on Windows Server Core but you'll need to RDP each node to make configuration. You can remotely failover script using failover cluster console. You **cannot** use PSSession since it will double hop the kerberos credentials if you do not have credentials delegation or CredSSP configured in your environment.
 - Same PSSCluster mode MUST be configure on all nodes.
 - PSSConfiguration are independant on each node.

> **Note**: This module as been tested on Windows Server 2019. There is no warranty it will work on older windows platform. You need to test it before using it in production environment.
> ****

## Modes

 ### Active/Active (recommended)
 - Each script are independant in the failover cluster. The script run on the owner of the cluster resource. 
 - Script execution is distributed over all nodes.
 - You can set prefered node to run specific scripts using failover cluster console.
 ### Active/Passive
 - All scripts runs on the owner of the cluster. You'll need to move cluster owner to move script to an other nodes. 
 > **Note**: In this mode, the owner of the resource are ignored. Only cluster owner node is the active in the cluster.
****

# Installation

> **Note**: We assume that you have configured your failover cluster, enabled quorum and installed Git SCM for windows. All PSSCluster logs are saved in event viewer at this location:
> **Eventvwr.msc -> Applications and Services Logs -> PSSCluster**

 1. Open windows powershell on the first cluster node.
 2. Enter the command: *New-PSSConfiguration*
 3. Select PSSCluster mode.
 4. Enter the master repository UNC path. It must exist, all nodes should have access to this share.
 5. Enter the local repository path. The folder should exist.
 6. Validate configuration and Enter: 'y'
 7. Repeat these steps on each nodes.

## Add a repository

 1. Open windows powershell on one of the cluster node.
 2. Enter the command: *New-PSSRepository -Name 'Repository Name'*
 > **Note**: The name of the repository must be unique.
 3. Verify that remote/local repository as been created.
 > **Note**: You can use the following command to get repositories: *Get-PSSRepository*
 You need to manually modified the scheduled task under:
 *Task Scheduler Library -> PSSCluster -> RepositoryName*.
 
 ## Edit wrapping script
 4.	From one of the nodes and/or a remote machines:
 *Git clone \\MasterRepositoryUNC\RepositoryName*
 5. Edit Bootstrap.ps1 with your prefered IDE and place your code into the indicated zone: *# Place your code here*
 6. Stages modifications:
 *Git add bootstrap.ps1* or Git add *
 7.	Create commit with your modifications:
 *Git commit -m 'Your commit informations.'*
8.	Push commit to production:
*Git push origin*
9.	Synchronize changes across all nodes executing the following command on each nodes:
*Sync-PSSRepositories*		
> **Note**:  If you do not manually synchronize changes with the above command, the commit will be automaticallty synchronize the next time the script runs on each nodes. The above command **MUST** be executed locally on the PSSCluster node. You cannot use PSSession since it will double hop the kerberos credentials if you do not have credentials delegation or CredSSP configured in your environment.
10. Validate that your changes as been propagated across nodes.
