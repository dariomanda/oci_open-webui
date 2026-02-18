# oci_open-webui

This repository provides a setup to easily run [Open WebUI](https://docs.openwebui.com/) on [Oracle Cloud Infrastructure (OCI)](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier.htm) fully integrated with LLMs within [Oracle Generative AI Service](https://docs.oracle.com/en-us/iaas/Content/generative-ai/home.htm).

[Open WebUI](https://docs.openwebui.com/) runs on a lightweight [OCI compute VM instance](https://docs.oracle.com/en-us/iaas/Content/Compute/Concepts/computeoverview.htm) with LLMs accessed by a [Python API service gateway](https://github.com/dariomanda/oci_open-webui/tree/main/api) by exposing an [OpenAI-compatible API](https://docs.openwebui.com/getting-started/quick-start/starting-with-openai-compatible/). Your  Open WebUI application service will thus talk to these LLMs hosted in the same OCI region.

[OpenTofu](https://opentofu.org/) scripts are provided to easily deploy infrastructure. [Ansible playbooks](https://docs.ansible.com/projects/ansible/latest/getting_started/index.html) are provided to set up software dependencies and to automate the deployment of the application with [Podman](https://github.com/containers/podman) or [Docker](https://docs.docker.com/). Additionally, [Let's Encrypt](https://letsencrypt.org/) is used to obtain secure SSL certificates for the frontend application, automatically making the application securely available under `https://`.

- [oci\_open-webui](#oci_open-webui)
- [Prerequisites](#prerequisites)
- [Quickstart](#quickstart)
  - [1. Create Compartment](#1-create-compartment)
  - [2. Dynamic Group](#2-dynamic-group)
  - [3. Create Policy](#3-create-policy)
  - [4. Deploy the Infrastructure with OpenTofu on OCI](#4-deploy-the-infrastructure-with-opentofu-on-oci)
    - [4.1 Create OpenTofu tfvars file](#41-create-opentofu-tfvars-file)
    - [4.2 Initialize OpenTofu and deploy the infrastructure](#42-initialize-opentofu-and-deploy-the-infrastructure)
    - [4.3 Verify whether instance principal access to OCI Generative AI Service is working](#43-verify-whether-instance-principal-access-to-oci-generative-ai-service-is-working)
  - [5. Set up DNS A record in your DNS provider](#5-set-up-dns-a-record-in-your-dns-provider)
  - [6. Provision and deploy Open WebUI with Ansible](#6-provision-and-deploy-open-webui-with-ansible)
    - [6.1 Prepare Open WebUI Ansible environment file](#61-prepare-open-webui-ansible-environment-file)
    - [6.2 Provision the host](#62-provision-the-host)
    - [6.3 Deploy Open WebUI with Ansible](#63-deploy-open-webui-with-ansible)
    - [6.4 Verify the deployment on the VM](#64-verify-the-deployment-on-the-vm)
    - [6.5 Log in to Open WebUI and create an admin account](#65-log-in-to-open-webui-and-create-an-admin-account)
  - [7. Model Selection](#7-model-selection)
- [Credits](#credits)


# Prerequisites

Our guide assumes that you have set up the following:  
* [Your own OCI tenancy (free tier available)](https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier.htm) 
* You have administrative access to a OCI tenancy.

Additionally you have installed the following tools locally:   
* [OCI Command Line Interface `oci`](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm)
* [OpenTofu](https://opentofu.org/docs/intro/install/)
* [Ansible Setup](https://docs.ansible.com/projects/ansible/latest/installation_guide/installation_distros.html)

If you are under MacOS, all these dependencies can be easily installed via [Homebrew](https://brew.sh/):
```bash
brew update
brew install ansible opentofu oci-cli  
```

# Quickstart

Please follow the guide below to set up your OCI environment and deploy the application .

## 1. Create Compartment

First, a compartment must be created where the future Open WebUI VM will reside.
As seen in the screenshot below, I created the ***open_webui*** compartment under a parent compartment (***Dario_Mandic***)

![Open WebUI Compartment](/docs/open_webui_compartment.png)

Head to [OCI Identity -> Compartments](https://cloud.oracle.com/identity/compartments), create a new compartment and make a note of your new unique compartment's OCID, like `ocid1.compartment.oc1..xxx`.

## 2. Dynamic Group
To allow [instance principals](https://blogs.oracle.com/developers/accessing-the-oracle-cloud-infrastructure-api-using-instance-principals) to authorize a compute instance to access OCI GenAI Service, we need to create a dynamic group first. Head to [OCI Identity -> Domains -> Dynamic Groups](https://cloud.oracle.com/identity/domains) for this. These dynamic groups should be typically created in your **default** identity domain. 

```All {instance.compartment.id = 'ocid1.compartment.oc1..xxx'}```

This dynamic group matches all instances in your provided compartment OCID (don't forget to change it with yours!).

![Dynamic Group](/docs/open-webui_dynamic_group.png)

To make it more restrictive, it is also possible to create a dynamic group for only one instance:

```Any {instance.id = 'ocid1.instance.oc1.eu-frankfurt-1.xxx'}```

## 3. Create Policy

Besides the compartment and the dynamic group, we also need to create a policy to allow instance principal access from the Open WebUI VM inside the *Open WebUI* compartment. Head to [OCI Identity -> Policies](https://cloud.oracle.com/identity/domains/policies) for this.

```Allow dynamic-group open-webui to use generative-ai-family in compartment open_webui```

As seen in the screenshot below, the *open_webui* compartment is only one level below the parent compartment *Dario_Mandic* (our your root compartment). Therefore, direct addressing of the *open_webui* compartment is possible.

![OCI GenAI access policy](/docs/genai_access_policy.png)

If you attach the policy two or more levels above the *open_webui* compartment, you'll need to specify the compartment path relative to the compartment where the policy is attached.
Here we have an example where the target compartment is two levels below the compartment where the policy is attached.

```Allow dynamic-group open-webui to use generative-ai-family in compartment <child>:<grandchild>:open_webui```


## 4. Deploy the Infrastructure with OpenTofu on OCI

Ensure that you have installed all [prerequisites](#prerequisites) and the OCI cli [is fully configured](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliconfigure.htm) before continuing. 

A very typical test command is listing your current Object Storage buckets (return code must be `0` even if you have none):
```bash
oci os bucket list
echo $?
# 0
```

### 4.1 Create OpenTofu tfvars file

You will need to copy the template file: `opentofu/terraform.tfvars.template` to `opentofu/terraform.tfvars` and update the content with real values for compartment ID, compute instance shape, OCI region, your public SSH key, etc.

```bash
cp opentofu/terraform.tfvars.template opentofu/terraform.tfvars
```

### 4.2 Initialize OpenTofu and deploy the infrastructure

After setting up the tfvars file, you can deploy the infrastructure with a few commands from the command line inside the ```opentofu/``` folder.

```bash
cd opentofu

# 1. Initialize OpenTofu
tofu init
# OpenTofu has been successfully initialized!

# 2. Apply the infrastructure
tofu apply

# Review the output and confirm with ```yes``` if everything is correct.

# After everything is finished you should receive a confirmation that everything is deployed:
Apply complete! Resources: 6 added, 0 changed, 0 destroyed.

Outputs:

public_ip = "xxx.xxx.xxx.xxx"
```

Note the public IP, because we will need it in the next step.

SSH into the created instance using the public IP from the output in the console to see if everything is working with: ```ssh ubuntu@xxx.xxx.xxx.xxx```

Logging into the compute instance over SSH is important because the server's public key needs to be added to the known_hosts file by logging in once. After doing this, Ansible playbooks, which are needed later, can be executed.

You will also see in the OCI console that the new instance is running:

![Open WebUI instance](/docs/open_webui_instance.png)

### 4.3 Verify whether instance principal access to OCI Generative AI Service is working

You can verify on the host VM if instance principal access is working for debugging purposes, but you'll need to set up OCI CLI on the host VM. Please refer to the [OCI CLI Setup Documentation for Linux](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm#InstallingCLI__linux_and_unix)

After OCI CLI is installed on the host VM, execute the following command to list the available models in your region. Just replace the correct compartment ID:


```bash
oci generative-ai model-collection list-models --auth instance_principal --compartment-id ocid1.compartment.oc1..xxx
```

## 5. Set up DNS A record in your DNS provider

Since Open WebUI is a web application, we need to create an **A record** in our DNS provider to point to the public IP of our VM.
We will use Traefik as a reverse proxy to get Let's Encrypt SSL certificates for the configured domain.

Let's say we have the following chat.mydomain.com for our Open WebUI application. Make sure to set this accordingly in your DNS provider, so that chat.mydomain.com resolves to the public IP from the previous output.

Below is an example, but the setup is slightly different for every DNS provider.
![A Record](/docs/a_record.png)

## 6. Provision and deploy Open WebUI with Ansible

Similar to opentofu/terraform, we expect that you have already installed all [prerequisites](#prerequisites) regarding Ansible.


### 6.1 Prepare Open WebUI Ansible environment file

All important environment variables must be set in a `.env` file. For this reason, an `.env_template` file can be found in the main folder of the repository and can be used as a reference.

```bash
# ensure your current working directory is the repository root folder again
cd ..

# copy the template
cp .env_template .env
```

These are the most important environment variables:

**`OCI_COMPARTMENT_ID=ocid1.compartment.oc1..xxx`**: This tells the `oci-openai-gateway` container in which compartment the OCI Generative AI Service will be used.

**`OCI_REGION=eu-frankfurt-1`**: Used in the `oci-openai-gateway` container and in the ```models.yml``` to set the correct OCI Region for LLM Inference

**`OPENAI_API_KEYS="sk-xxx"`**: This environment variable is used by the `oci-openai-gateway` container to expose an OpenAI-compatible API, secured by an API key. The same API key is used by the `open-webui` container to authenticate to the `oci-openai-gateway` container, meaning it's all internally. Simply replace `xxx` with an unique value, e.g. [an UUIDv4](https://www.uuidgenerator.net/version4).


**`WEBUI_SECRET_KEY=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx`**: This variable is used for persistent sessions through restarts of the container applications. Similar to above, insert a random value here, e.g. [an UUIDv4](https://www.uuidgenerator.net/version4).

**`WEBUI_URL=https://example.com`**: The public domain (as you've set your A record)

**`WEBUI_HOST=example.com`**: This is again important for Open WebUI to function correctly, but also by the Traefik reverse proxy container to obtain Let's Encrypt SSL certificates.


### 6.2 Provision the host 
We will provision the host with Podman and Docker Compose. To set up Podman with all dependencies, execute the following Ansible playbook (do not forget the comma after the IP address; it is important):

```bash
ansible-playbook -u ubuntu ansible/podman_deployment/podman_setup.yml -i xxx.xxx.xxx.xxx,
```

### 6.3 Deploy Open WebUI with Ansible

After Podman is installed, you can deploy the containers (Traefik + Open WebUI + OCI Gateway) with the following playbook:

```bash
ansible-playbook -u ubuntu ansible/podman_deployment/deploy_openwebui.yml -i xxx.xxx.xxx.xxx,
```

### 6.4 Verify the deployment on the VM

SSH into the instance and check that the stack is up:

```bash
ssh ubuntu@xxx.xxx.xxx.xxx
sudo su
podman ps
```

### 6.5 Log in to Open WebUI and create an admin account

After executing the deployment Ansible playbook, wait two minutes and give the Traefik reverse proxy some time to retrieve Let's Encrypt SSL certificates for your domain.

When everything is finished, open your domain in the browser and create an administrator account for Open WebUI and start chatting :)

![Create Admin Account](/docs/create_admin_account.png)

## 7. Model Selection

LLMs and embedding models can be defined in the ```models.yaml``` file.

```yaml
- region: ${OCI_REGION}
  compartment_id: ${OCI_COMPARTMENT_ID}
  models:
    ondemand:
      - name: cohere.command-plus-latest
        model_id: cohere.command-plus-latest
        description: "delivers roughly 50% higher throughput and 25% lower latencies as compared to the previous Command R+ version, while keeping the hardware footprint the same."
        "tool_call": True,  
        "stream_tool_call": True,  

      - name: cohere.command-latest
        model_id: cohere.command-latest
        description: "delivers roughly 50% higher throughput and 25% lower latencies as compared to the previous Command R+ version, while keeping the hardware footprint the same."
        "tool_call": True,  
        "stream_tool_call": True,  

      - name: meta.llama-3.3-70b-instruct
        model_id: meta.llama-3.3-70b-instruct
        description: "Model has 70 billion parameters. Accepts text-only inputs and produces text-only outputs. Delivers better performance than both Llama 3.1 70B and Llama 3.2 90B for text tasks. Maximum prompt + response length is 128,000 tokens for each run. For on-demand inferencing, the response length is capped at 4,000 tokens for each run."
        "tool_call": True,
        "stream_tool_call": True,
      
      - name: openai.gpt-oss-120b
        model_id: openai.gpt-oss-120b
        description: "gpt-oss-120b"
        "tool_call": True,  
        "stream_tool_call": True, 

      - name: openai.gpt-oss-20b
        model_id: openai.gpt-oss-20b
        description: "gpt-oss-20b"
        "tool_call": True,  
        "stream_tool_call": True,

      - name: google.gemini-2.5-flash
        model_id: google.gemini-2.5-flash
        description: "google.gemini-2.5-flash"
        "tool_call": True,  
        "stream_tool_call": True,
        "multimodal": True,

      - name: google.gemini-2.5-flash-lite
        model_id: google.gemini-2.5-flash-lite
        description: "google.gemini-2.5-flash-lite"
        "tool_call": True,  
        "stream_tool_call": True,
        "multimodal": True,

      - name: google.gemini-2.5-pro
        model_id: google.gemini-2.5-pro
        description: "google.gemini-2.5-pro"
        "tool_call": True,  
        "stream_tool_call": True,
        "multimodal": True,

    embedding:
      - name: cohere.embed-multilingual-v3.0
        model_id: cohere.embed-multilingual-v3.0
        description: "Cohere multilingual embedding model v3.0"
```

# Credits

**The credits of the OCI OpenAI-compatible API Gateway application go to:**

* [Oracle technology-engineering](https://github.com/oracle-devrel/technology-engineering/tree/main/ai/gen-ai-agents/agents-oci-openai-gateway)
* and to **jin38324**'s [modelsOCI-toOpenAI](https://github.com/RETAJD/modelsOCI-toOpenAI/tree/main)