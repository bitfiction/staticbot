# PersistentVolumeClaims backed by DO Block Storage CSI driver

resource "kubernetes_persistent_volume_claim" "db_data" {
  metadata {
    name      = "db-data"
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "do-block-storage"
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "storage_data" {
  metadata {
    name      = "storage-data"
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "do-block-storage"
    resources {
      requests = {
        storage = "10Gi"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "functions_data" {
  metadata {
    name      = "functions-data"
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "do-block-storage"
    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}

# Studio's local SQL snippets (SNIPPETS_MANAGEMENT_FOLDER)
resource "kubernetes_persistent_volume_claim" "studio_snippets" {
  metadata {
    name      = "studio-snippets"
    namespace = kubernetes_namespace.supabase.metadata[0].name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "do-block-storage"
    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}
