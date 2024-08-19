output "helm_release_status" {
  value = helm_release.helm_charts[*].status
}