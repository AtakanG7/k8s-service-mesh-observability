output "zipkin_service_name" {
  value = kubernetes_service.zipkin.metadata[0].name
}