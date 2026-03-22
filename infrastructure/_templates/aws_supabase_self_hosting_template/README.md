# 20251222

The following files have been created in infrastructure/_templates/aws_supabase_self_hosting_template/:

   1. `variables.tf`: Contains all variables extracted from docker-compose.yml and generic AWS variables.
   2. `network.tf`: Sets up VPC, Subnets (Public/Private), NAT Gateway, Security Groups, and ALB.
   3. `efs.tf`: Configures EFS for persistent storage (db, storage, functions) with specific Access Points.
   4. `ecs.tf`: Defines the ECS Cluster, Cloud Map (Service Discovery) namespace supabase.internal, and IAM Roles.
   5. `logs.tf`: Sets up CloudWatch Log Group.
   6. `ecs-services-data.tf`: Task definitions and Services for Data Layer (db, vector).
       * Note: The db task injects SQL init scripts (from your local docker/volumes/db) via environment variables and writes them to the container on startup.
   7. `ecs-services-core.tf`: Task definitions and Services for Core Layer (auth, rest, realtime, storage, imgproxy).
       * Note: Services communicate via http://<service-name>.supabase.internal.
   8. `ecs-services-gateway.tf`: Task definitions and Services for Gateway/UI (kong, studio, meta, functions, analytics, supavisor).
       * Note: kong.yml is injected with replaced hostnames to match the ECS Service Discovery names (e.g., realtime-dev.supabase-realtime -> realtime.supabase.internal).
   9. `main.tf`: Provider configuration.
   10. `outputs.tf`: Outputs the ALB DNS name and Service URLs.
   11. `terraform.tfvars.example`: Example variable values.

  Key Implementation Details:
   * Storage: EFS is used for all persistent volumes (/var/lib/postgresql/data, /var/lib/storage, etc.).
   * Config Files: Configuration files (kong.yml, vector.yml, SQL scripts) are read from your local docker/ directory by Terraform (file()) and injected into the containers as Environment Variables. A wrapper command in the Task Definition writes them to
     the expected file path before starting the application.
   * Networking: All services run in private subnets. kong and studio are exposed via the public ALB.
   * Service Discovery: AWS Cloud Map is used. Services can reach each other at hostname.supabase.internal (e.g., db.supabase.internal).

  You can now review terraform.tfvars.example, create a terraform.tfvars, and run terraform init / apply.