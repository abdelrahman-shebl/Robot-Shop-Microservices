variable "secrets_map" {
  description = "A map containing all secrets from the YAML file"
  type        = any 
}

variable "opencost_integration_json" {
  description = "The JSON content for the OpenCost cloud-integration secret"
  type        = string
  default     = ""
}