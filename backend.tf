terraform {
  backend "gcs" {
    bucket = "product-landing-terraform-state"
    prefix = "env/product-landing"
  }
}
