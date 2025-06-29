# Vault Agent Configuration

# Vault server configuration
vault {
  address = "http://vault:8200"
  retry {
    num_retries = 5
  }
}

# Auto-auth configuration
auto_auth {
  method "aws" {
    mount_path = "auth/aws"
    config = {
      type = "iam"
      role = "vault-agent-role"
    }
  }

  sink "file" {
    config = {
      path = "/vault/secrets/.vault-token"
    }
  }
}

# Template configurations for secret injection
template {
  source      = "/vault/config/database.tpl"
  destination = "/vault/secrets/database.env"
  perms       = 0600
  command     = "restart app"
}

template {
  source      = "/vault/config/api-keys.tpl"
  destination = "/vault/secrets/api-keys.json"
  perms       = 0600
}

template {
  source      = "/vault/config/certificates.tpl"
  destination = "/vault/secrets/tls.crt"
  perms       = 0644
}

# Cache configuration
cache {
  use_auto_auth_token = true
}

# Listener for agent API
listener "tcp" {
  address = "127.0.0.1:8100"
  tls_disable = true
}

# Logging
log_level = "INFO"
log_file = "/vault/logs/agent.log"
