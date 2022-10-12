# Specify the GCP Provider
provider "google" {
  project = var.project_id
  region  = var.region
}

data "google_compute_image" "ubuntu" {
  family  = "ubuntu-2204-lts"
  project = "ubuntu-os-cloud"
}

# Creates a GCP VM Instance.  Metadata Startup script install the Nginx webserver.
resource "google_compute_instance" "vm" {
  name         = var.name
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["web"]

  boot_disk {
    initialize_params {
      image = data.google_compute_image.ubuntu.self_link
    }
  }

  network_interface {
    network = "default"
    access_config {
      // Ephemeral IP
    }
  }

  metadata_startup_script = data.template_file.nginx.rendered
}

resource "google_compute_firewall" "default" {
 name    = "web-firewall"
 network = "default"

 allow {
   protocol = "icmp"
 }

 allow {
   protocol = "tcp"
   ports    = ["80"]
 }

 source_ranges = ["0.0.0.0/0"]
 target_tags = ["web"]
}

data "template_file" "nginx" {
  template = "${file("nginx.tpl")}"

  vars = {
    ufw_allow_nginx = "Nginx HTTP"
  }
}

output "webserver_ip" {
value = google_compute_instance.vm.network_interface.0.access_config.0.nat_ip
}