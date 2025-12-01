<h1 align="center">Unpark.ai</h1>

<p align="center">
  <i>You own the domain. It's time to launch the project.</i>
  <br />
  Unpark turns your forgotten domains into real projects in minutes.
  <br />
  AI ideas → AI copy → AI design → deployed instantly.
  <br />
  <a href="https://www.unpark.ai/"><strong>Learn more at unpark.ai</strong></a>
</p>

---

[Unpark.ai](https://www.unpark.ai/) (formerly Staticbot) helps founders and SaaS businesses deploy and manage static websites directly within their own AWS accounts. It provides reliable, cost-effective hosting using S3 and CloudFront, with complete transparency and no vendor lock-in. You always own your infrastructure.

While Unpark.ai is designed with a multi-cloud vision for the future, **currently, it exclusively supports AWS.** We plan to expand to other cloud providers.

## Why Unpark.ai?

-   **Own Your Infrastructure & Cut Costs**: Deploy for free to your own AWS account, keeping full control, eliminating third-party hosting fees, and only paying for AWS resources.
-   **No Vendor Lock-in**: Export the Terraform code at any time and continue using your infrastructure without Unpark.ai.
-   **Global Performance & Reliability**: Leverages AWS S3 and CloudFront for fast load times, global CDN distribution, and high availability.
-   **Effortless Custom Domains & SSL**: Easily connect your custom domains. Unpark.ai handles SSL certificate provisioning and renewals via AWS Certificate Manager.
-   **AI Builder Integration**: Seamlessly integrates with tools like Lovable.dev and other AI builders via GitHub for streamlined development workflows.
-   **Private Repository Support**: Supports private GitHub repos, perfect for nights & weekends projects, internal tools, or client work while maintaining privacy.
-   **Complete Transparency**: The underlying Terraform infrastructure code is always available, allowing you to take over and manage it independently whenever you wish.
-   **Cost-Effective**: Pay only for the AWS resources you use, avoiding expensive PaaS markups.
-   **Stage-Based Deployments**: Supports multiple deployment stages (e.g., dev, preview, www) per website.
-   **Advanced Hosting Features**: Includes custom error pages, intelligent redirects (language/region, WWW/non-WWW), and maintenance mode support.

## How It Works

This repository contains a reusable, modular Terraform setup for deploying static websites on AWS. The core components are:

-   **S3**: For storing your website's static files.
-   **CloudFront**: A global Content Delivery Network (CDN) for fast, secure content delivery.
-   **Route 53**: For managing your custom domain's DNS records.
-   **ACM (AWS Certificate Manager)**: For free, auto-renewing SSL/TLS certificates.

### Deployment

The infrastructure is managed per-account. All configuration and deployment commands are run from within this repository. For detailed technical instructions on how to deploy a new website or migrate an existing one, please see the infrastructure guide:

-   **[AWS Infrastructure Deployment Guide](./infrastructure/cloud_aws/README.md)**

---
