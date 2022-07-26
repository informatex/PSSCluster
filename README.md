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
 - Template wrapping script is automatically created with new repositories
 - Automatically put uncompliant nodes in maintenance mode.

## Prerequisites

 - Windows Git x64 must be installed on each nodes.
 https://git-scm.com/download/win
 - Windows Failover Cluster must be configures prior to configure PSSCluster.
 https://docs.microsoft.com/en-us/windows-server/failover-clustering/failover-clustering-overview
 - Failover Cluster Quorum should be configured.
 https://docs.microsoft.com/en-us/windows-server/failover-clustering/manage-cluster-quorum

## Restrictions

You can use this module on Windows Server Core but you'll need to RDP each node to make configuration. You can remotely failover script using failover cluster console.

Same PSSCluster mode MUST be configure on all nodes.

PSSConfiguration are independant on each node.

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
