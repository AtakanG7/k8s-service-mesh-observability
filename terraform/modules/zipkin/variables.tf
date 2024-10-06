variable "namespace" {
  description = "Kubernetes namespace to deploy Zipkin"
  type        = string
  default     = "istio-system"
}