project_name = "nt531"
region       = "ap-southeast-1"

# --- Version pinning ---
kubernetes_version = "1.34"
cilium_version     = "1.18.7"

# --- Node group ---
instance_type          = "t3.large"
node_count             = 3
endpoint_public_access = true
