project_name       = "nt531-netperf"
region             = "ap-southeast-1"

# --- Version pinning (khuyến nghị ổn định nhất) ---
kubernetes_version = "1.34"      # fallback: "1.33" nếu region/account chưa có 1.34
cilium_version     = "1.18.7"    # latest patch of 1.18.x

# --- Node group ---
instance_type          = "t3.large"
node_count             = 3       # min = desired = max = 3 (no autoscaling)
endpoint_public_access = true
