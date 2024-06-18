output "drain_topic_id" {
  value = google_pubsub_topic.k8s_node_draining_topic.id
}

output "instance_state_bucket_name" {
  value = google_storage_bucket.instance_state_bucket.name
}