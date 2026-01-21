# Description

This repository packages multiple Docker containers to easily deploy Open WebUI on a lightweight OCI Compute VM. It integrates Open WebUI with LLMs deployed in Oracle Generative AI Service via a gateway Python application, by exposing an OpenAI Compatible API, so that Open WebUI talk to LLMs hosted by the Oracle Generative AI Service.
Additionally, Letsencrypt is used to obtain secure LetsEncrypt SSL Certificates for the frontend application.

OpenTofu scripts are provided to easily deploy Infrastructue.

Ansible playbooks are provided to setup software dependencies and to automate the deployment of the Application with Podman and Docker.

# Please follwo the below guide to Setup your OCI Environment and deploy the application

# 1. Create Compartment

At first, a compartment must be created, where the future OpenWebui VM will reside.
As seen in the sccreenshot below, I created the ***open_webui*** Compartment under a parent Compartment (***Dario_Mandic***)

![Open WebUI Compartment](/docs/open_webui_compartment.png)


# 2. Dynamic Group
To allow instance principal access to OCI GenAI Service, we need to create a dynamic group first. The dynamic group is createrd in the **Default** Identity Domain.

```All {instance.compartment.id = 'ocid1.compartment.oc1..xxx'}```

This dynamci group matches all instances in the provided compartement id.

![Dynamic Group](/docs/open-webui_dynamic_group.png)

To make it more restrictive, it is also possible to create a dynameic group for only one instance:

```Any {instance.id = 'ocid1.instance.oc1.eu-frankfurt-1.xxx'}```

# 3. Create Policy

Beside the Compartment and the Dynamic Group, we also need to create a Policy, to allow Instance Principal access from the Open WebUI VM inside the *Open WebUI* Compartment.

```Allow dynamic-group open-webui to use generative-ai-family in compartment open_webui```

As seen in the Screenshot below, the *open_webui* compartment is only one level below the Parent Compartment *Dario_Mandic*, therefore, direct addressing of the *open_webui* Comaprtment is possible.

![OCI GenAI access policy](/docs/genai_access_policy.png)

If you attach the policy two or more levels above the *open_webui* compartment, you'll need to specify the compartment path relative to the compartment, where the policy is attached.
here we have an example, where the target Compartment is two levels below the Compartment, where the Policy is attached.

```Allow dynamic-group open-webui to use generative-ai-family in compartment <child>:<grandchild>:open_webui```


# 4. Deploy the Infrastructure with OpenTofu in OCI

We use OCI CLI and OpenTofu do deploy our infrastructure in OCI.
To install OCI CLI and OpenTofu for your system, please refer to the following documentation:

* [OCI CLI Quickstart](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm)
* [OpenTofu Installation](https://opentofu.org/docs/intro/install/)

## 4.1 Create OpenTofu tfvars file

After installing and Configuraing OCI CLI and installing OpenTofu, you will need to copy the template file: ```opentofu/terraform.tfvars.template``` to ```opentofu/terraform.tfvars``` and update the content with real values for Compartment ID, Compute Instance Shape, OCI Region, your public SSH key, etc.

## 4.2 Initialize Opentofu and deploy the Infrastructure

After having setting up the tfvars file, you can deploy the infrastructure with a few commands from the command line inside the ```opentofu/``` folder.

1. Initialize OpenTofu: ```tofu init``` <br />
The Output should be something like: <br />
```OpenTofu has been successfully initialized!```
2. Apply the Infrastructure: ```tofu apply``` <br />
Review the output and confirm with ```yes```if everything is correct.

after everything is finished you should receive a confirmation that everything is deployed:

```
Apply complete! Resources: 6 added, 0 changed, 0 destroyed.

Outputs:

public_ip = "xxx.xxx.xxx.xxx"
```

Note the Public IP, because we will need it in the next step.

SSH into the created instance, by using the Public IP from the output in the console to see if everything is working with: ```ssh ubuntu@xxx.xxx.xxx.xxx```

Logging into the compute instance over SSH is important, because th servers public key needs to be added to the know_hosts file by logging in once. After doing this, ansible playbooks, which are needed later can be executded.

You will also see in the OCI console that the new instance is running:

![Open WebUI instance](/docs/open_webui_instance.png)

## 4.3 Verify if Instance Principal access to OCI Generative AI Service is working:

You can verify on the host VM if Instance Principal access is working for debugging purposes, but you'll need to setup oci cli on the host VM. Please refer to the [OCI CLI Setup Documentation for Linux](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm#InstallingCLI__linux_and_unix)

After OCI CLI is installed on the host VM, execute the following command to list the available models in your region. Just replace the correct compartment ID:


```oci generative-ai model-collection list-models --compartment-id ocid1.compartment.oc1..xxx --auth instance_principal```

# 5. Setup DNS A Record in your DNS Provider

Since Open WebUI is a Web Application, we need to create a **A Record** in our DNS Provider to point to the Public IP of our VM.
We will use Traefik as a reverse Proxy to get LetsEncrypt SSL Certificates for the configured domain.

Lets say we have the following chat.mydomain.com for our Open WebUI application. Make sure to Setup this acordingly in your DNS provider, so that chat.mydomain.com resolves to the Public IP from the previous output.

Below is an example, but the setup is slightly different for every DNS Provider.
![A Record](/docs/a_record.png)

# 6. Install software dependencies with Ansible and deploy the OpenWebui

## 6.1 Install Ansible on your machine
We use ansible to automate the Software Installation. Refer to the Ansible documentation to setup Ansible on your machine:

* [Ansible Setup for Linux](https://docs.ansible.com/projects/ansible/latest/installation_guide/installation_distros.html)

* [Ansible Setup for Mac with Homebrew](https://formulae.brew.sh/formula/ansible)

### 6.1.1 Prepare Open WebUI environment file

All important environment file must be set in a ```.env``` file. For this reason, an ```.env_template```file can be found in the main folder of the repository and can be used as an reference.

These are the most important environment files, which must be set:

*OCI_COMPARTMENT_ID=ocid1.compartment.oc1..xxx*

This tells the ```oci-openai-gateway``` container in which compartment the OCI Generative AI Service will be used.


*OPENAI_API_KEYS="sk-xxx"*

This environment Variable is used by the ```oci-openai-gateway``` container to expose an OpenAI Compatible API, secured by an API Key. The same API Key is used by the ```open-webui``` container to authenticate to the ```oci-openai-gateway``` container.


*WEBUI_SECRET_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx*

This variable is used for Persistent Sessions throgh restarts of the container applications.


*WEBUI_URL=https://example.com*

*WEBUI_HOST=example.com*

These are importnt for Open WebUI to function correctly, but also by the Traefik Reverse Proxy Container to obtain LetsEncrypt SSL Certificates.



###

## 6.2 Install Podman with Ansible
We will deploy the application with Podman and docker compose. To setup podman with all dependencies, execute the following ansible playbook (do not forget the comma after the IP Address, it is important):

```ansible-playbook -i xxx.xxx.xxx.xxx, -u ubuntu ansible/podman_deployment/podman_setup.yml```

## 6.3 Deploy Open WebUI with Ansible

After Podman is installed, you can deploy the containers (Traefik + Open WebUI + OCI Gateway) with the following playbook:

```ansible-playbook -i xxx.xxx.xxx.xxx, -u ubuntu ansible/podman_deployment/deploy_openwebui.yml```

## 6.4 Verify the deployment on the VM

SSH into the instance and check that the stack is up:

```sudo podman ps```

## 6.5 Login into Open WebUI and create admin Account

After executing the deployment Ansible playbook, wait two minutes and give Traefik Reverse Proxy some time to retreive LetsEncrypt SSL Certificates for your domain.

When everything is finished, open your domain in the browser and create an Administrator Account for Open WebUI and start chatting :)

![Create Admin Account](/docs/create_admin_account.png)
