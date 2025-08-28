<h1 align="center">Staticbot</h1>

<p align="center">
  <i>How Founders deploy static websites.</i>
  <br />
  Host landing pages and email capture sites inside your own AWS account.
  <br />
  Infrastructure code available - no lock in.
  <br />
  <a href="https://www.staticbot.dev/"><strong>Learn more at staticbot.dev</strong></a>
</p>

---

[Staticbot](https://www.staticbot.dev/) helps founders and SaaS businesses deploy and manage static websites directly within their own AWS accounts. It provides reliable, cost-effective hosting using S3 and CloudFront, with complete transparency and no vendor lock-in. You always own your infrastructure.

While Staticbot is designed with a multi-cloud vision for the future, **currently, it exclusively supports AWS.** We plan to expand to other cloud providers.

![Staticbot Dashboard](https://www.staticbot.dev/staticbot_dashboard_3.png)

## Why Staticbot?

-   **Own Your Infrastructure & Cut Costs**: Deploy for free to your own AWS account, keeping full control, eliminating third-party hosting fees, and only paying for AWS resources.
-   **No Vendor Lock-in**: Export the Terraform code at any time and continue using your infrastructure without Staticbot.
-   **Global Performance & Reliability**: Leverages AWS S3 and CloudFront for fast load times, global CDN distribution, and high availability.
-   **Effortless Custom Domains & SSL**: Easily connect your custom domains. Staticbot handles SSL certificate provisioning and renewals via AWS Certificate Manager.
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
