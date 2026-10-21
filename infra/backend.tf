terraform {
  backend "kubernetes" {
    secret_suffix = "test"
    config_path   = "/tmp/kubie-configKA1Igz.yaml"
    namespace     = "flux-system"
  }
}