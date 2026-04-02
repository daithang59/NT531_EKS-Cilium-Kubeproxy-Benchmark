project_name = "nt531"
region       = "ap-southeast-1"

# --- Version pinning ---
kubernetes_version = "1.34"
cilium_version     = "1.18.7"

# --- Node group ---
instance_type          = "m5.large"
node_count             = 3       # min = desired = max = 3 (no autoscaling)
endpoint_public_access = true
