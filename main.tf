terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
    }
    docker = {
      source  = "kreuzwerker/docker"
    } 
  }
}

locals {
  username = data.coder_workspace.me.owner
}

data "coder_provisioner" "me" {
}

provider "docker" {

}

provider "coder" {
  feature_use_managed_variables = "true"
}

data "coder_workspace" "me" {}


resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"
  dir = "/home/${local.username}"
  startup_script = <<EOT
#!/bin/bash

# clone coder/coder repo
mkdir -p ~/.ssh
ssh-keyscan -t ed25519 github.com >> ~/.ssh/known_hosts

# install and start code-server
code-server --auth none --port 13337 &

  EOT 

  env = {
    GIT_AUTHOR_NAME     = "${data.coder_workspace.me.owner}"
    GIT_COMMITTER_NAME  = "${data.coder_workspace.me.owner}"
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace.me.owner_email}"
    GIT_COMMITTER_EMAIL = "${data.coder_workspace.me.owner_email}"
    DOCKER_USER = "${local.username}"
  }
}

# code-server
resource "coder_app" "code-server" {
  agent_id      = coder_agent.main.id
  slug          = "code-server"  
  display_name  = "VS Code Web"
  icon          = "/icon/code.svg"
  url           = "http://localhost:13337?folder=/home/${local.username}"
  subdomain = false
  share     = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 3
    threshold = 10
  }  
}

resource "docker_container" "dind" {
  count   = data.coder_workspace.me.start_count  
  image      = "docker:dind"
  privileged = true
  network_mode = "host"
  name       = "dind-${data.coder_workspace.me.id}"
  entrypoint = ["dockerd", "-H", "tcp://0.0.0.0:2375"]
}


resource "docker_image" "main" {
  name = "coder-${data.coder_workspace.me.id}"
  build {
    context = "./build"
    build_args = {
      USER = local.username
    }
  }
  triggers = {
    dir_sha1 = sha1(join("", [for f in fileset(path.module, "build/*") : filesha1(f)]))
  }
}

resource "docker_container" "workspace" {
  count   = data.coder_workspace.me.start_count
  image   = docker_image.main.name
  name    = "dev-${data.coder_workspace.me.id}"
  command = ["sh", "-c", coder_agent.main.init_script]
  network_mode = "host"
  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "DOCKER_HOST=localhost:2375",
    "DOCKER_USER=${local.username}"
  ]
  volumes {
    container_path = "/home/${local.username}/"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }    
}

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }
  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace.me.owner
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace.me.owner_id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  # This field becomes outdated if the workspace is renamed but can
  # be useful for debugging or cleaning out dangling volumes.
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = docker_container.workspace[0].id
  item {
    key   = "Docker host name"
    value = "localhost:2375"
  }       
  item {
    key   = "image"
    value = "docker.io/codercom/enterprise-base:ubuntu"
  }
  item {
    key   = "repo cloned"
    value = "docker.io/coder/sharkymark/flask-redis-docker-compose.git"
  }     
}
