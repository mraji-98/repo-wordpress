provider "google"{
  credentials="SAKEY.json"
  project ="gcp-training-01-303001"
  region ="us-central1"   
  zone ="us-central1-c"
}

resource "google_compute_network" "vpc-net"{
  name="rajyalakshmi-terraform-vpc"
  auto_create_subnetworks = "false"
  routing_mode = "REGIONAL"
}
resource "google_compute_subnetwork" "vpc-subnet" {
  name = "rajyalakshmi-terraform-subnet"
  region = "us-central1"
  ip_cidr_range="10.25.2.1/24"
  depends_on    = [google_compute_network.vpc-net]
  network= "rajyalakshmi-terraform-vpc"
}
resource "google_compute_firewall" "vpcf" {
  name    = "rajyalakshmi-terraform-firewall"
  network = "rajyalakshmi-terraform-vpc"

  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["22","80"]
  }
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_instance_template" "tmp1" {
  name = "rajyalakshmi-mig-tmp"
  machine_type            = "f1-micro"
  metadata_startup_script = file("wp.sh")
  region                  = "us-central1"
  tags = [ "http-server","http","https","allow-iap-ssh","allow-http"]

  disk {
    source_image = "debian-cloud/debian-9"
    disk_size_gb = 10
    auto_delete  = true
    boot         = true
  }

  network_interface {
    network = "rajyalakshmi-terraform-vpc"
   subnetwork = "rajyalakshmi-terraform-subnet"
   access_config {
        }
  }

}

resource "google_compute_region_instance_group_manager" "mig-grp" {
  name               = "rajyalakshmi-mig"
  region             = "us-central1"
  base_instance_name = "rajyalakshmi-mig-ins"
  target_size        = 2

version {
instance_template  = google_compute_instance_template.tmp1.id
}
  
  named_port {
    name = "http"
    port = 80
  }
  
  named_port {
    name = "https"
    port = 443
  }
}

resource "google_compute_region_autoscaler" "wpex" {
  name   = "rajyalakshmi-my-region-autoscaler"
  region = "us-central1"
  target = google_compute_region_instance_group_manager.mig-grp.id

  autoscaling_policy {
    max_replicas    = 3
    min_replicas    = 1
    cooldown_period = 60

    cpu_utilization {
      target = 0.6
    }
  }
}

//Reserve Static IP
resource "google_compute_global_address" "sip" {
  name = "rajyalakshmi-static-ip"
  ip_version   = "IPV4"
  address_type = "EXTERNAL"
}

//Load Balancer 
resource "google_compute_http_health_check" "hc" {
  name         = "rajyalakshmilb-health-check"
  request_path = "/health"

  timeout_sec        = 5
  check_interval_sec = 5
  tcp_health_check {
    port = "80"
  }
}

resource "google_compute_backend_service" "backend" {
  name             = "rajyalakshmi-wp-backend"
  protocol         = "HTTP"
  timeout_sec      = 10
  session_affinity = "NONE"

  backend {
    group = google_compute_region_instance_group_manager.mig-grp.instance_group
  }
  health_checks = [google_compute_http_health_check.hc.id]
   
}

resource "google_compute_global_forwarding_rule" "lbfw" {
  name       = "rajyalakshmilb-fw-rule"
  ip_address = google_compute_global_address.sip.address
  port_range = "80"
  target     = google_compute_target_http_proxy.proxy.self_link
  all_ports  = true
}

resource "google_compute_url_map" "mapping" {
  name        = "rajyalakshmilb-url-map"
  default_service = google_compute_backend_service.backend.self_link
}

resource "google_compute_target_http_proxy" "proxy" {
  name    = "rajyalakshmilb-proxy"
  url_map = google_compute_url_map.mapping.self_link
}

//SQL instance
resource "google_sql_database_instance" "wp-ins" {
  name   = "rajyalakshmi-wpdb-inst"
  database_version = "MYSQL_5_6"
  
  settings {
    tier              = "db-f1-micro"
    availability_type = "REGIONAL"
    disk_size         = "10"

    backup_configuration {
      binary_log_enabled = true
      enabled = true
    }
    ip_configuration {
      ipv4_enabled    = true    
  }
}
  deletion_protection  = "false"
}
