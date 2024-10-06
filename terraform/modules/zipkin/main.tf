resource "kubernetes_deployment" "zipkin" {
  metadata {
    name = "zipkin"
    namespace = var.namespace
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "zipkin"
      }
    }

    template {
      metadata {
        labels = {
          app = "zipkin"
        }
      }

      spec {
        container {
          image = "openzipkin/zipkin"
          name  = "zipkin"

          port {
            container_port = 9411
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "zipkin" {
  metadata {
    name = "zipkin"
    namespace = var.namespace
  }
  spec {
    selector = {
      app = "zipkin"
    }
    port {
      port        = 9411
      target_port = 9411
    }
  }
}