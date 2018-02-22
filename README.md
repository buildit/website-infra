# Website infrastructure provisioning

## Prerequisites

To provision a website infrastructure you need:

- Credentials of an AWS able with permissions to manage S3 buckets, CloudFront, Route53, Lambda and using CloudFormation
- A valid SSL certificate in ACM *Region us-east-1* for the custom domain. Certificates is loaded in any other reagion are not available to CloudFront
- A custom DNS Zone hosted on Route53. The website DNS record will be added (may be a sub-domain or APEX)

**TBD** Serverless requirements: Node, SLS...

Scripts expect AWS CLI being configured, either with `aws configure` or setting  `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` env variables.

The Region is defined in the environment configuration file (see below) so the default Region is irrelevant.

## Description of the infra

- CloudFront Distribution with a default behaviour pointing to *main* Origin: an S3 bucket
    - Distribution is https only (http redirects to https)
    - Custom domain, hosted on Route53
    - A valid SSL certificate is required for https on the custom domain
- Optionaly, creates a second *experiment* Origin for A/B testing
- S3 bucket for website content (*main*)
- Optionally, a second S3 bucket for *experiment* website, to be used for A/B testing
- Optionally, another S3 bucket to store CloudFront logs
- A DNS record (an *Alias* Route53 record) aliasing the CloudFront endpoint in the custom domain. May be any subdomain of the Hosted Zone or the APEX of the zone. The DNS record is created with a separate operation, to enable operations like switching traffic from an existing website
- If the *Experiment* website S3 bucket is specified, A/B testing may be enabled later (see below) 

## Provision infrastructure for a single environment

A single website environment (e.g. "Production" or "Staging") is defined by a configuration file.

Scripts are used to trigger CloudFormation to make modification to resource.
The actual work of modifying resources is done by CloudFormation asyncrhonously, but these scripts explicitly wait util the modification is complete or failed.

CloudFormation creates names *Stacks*.
Names and Region of stacks are part of the environment configuration, in the configuration file.

As CloudFormation Stack names are unique in a AWS Account+Region. Also, an environment creates resources with a unique naming, either by Region or globally (like S3 bucket).
This means you cannot create multiple instances of the same environment (using the same environment configurazion file).

## Environment configuration file

The environment config file completely define one environment.

It defines the CloudFormation stack name prefix and names of resources to be created.

A configuration file must define all the following variables:

- `ENV_NAME` Name if the environment used as base name for the CloudFormation stacks. Alphanumeric an hyphens only.
- `RESOURCES_REGION` All S3 buckets and CloudFormation template go into this Region. Other resources are global or are always deployed in `us-east-1`
- `SITE_BUCKET` Name of the S3 bucket that will host the (main version of) the website. Must be a valid S3 bucket name (globally unique, valid DNS name)
- `AB_EXPERIMENT_BUCKET` (optional) Name of the S3 bucket that will host the A/B testing experiment version of the webiste. If omitted, A/B testing will not be available. Must be a valid S3 bucket name (globally unique, valid DNS name)
- `LOGS_BUCKET` (optional) Name of the bucket that will store CloudFront logs. Must be a valid S3 bucket name (globally unique, valid DNS name)

- `WEBISTE_DNS_NAME` FQ DNS name. Must be in the specified domain, but may be the APEX
- `WEBSITE_DOMAIN` Must match a Route53 Hosted Zone
- `CERTIFICATE_ARN` ARN of an SSL certificate already loaded in ACM **`us-east-1` Region**, for the website DNS name
- `CDN_PRICE_CLASS` ('PriceClass_All', 'PriceClass_200' or 'PriceClass_100') See [CloudFront API Reference](https://docs.aws.amazon.com/cloudfront/latest/APIReference/API_CreateDistribution.html#cloudfront-CreateDistribution-request-PriceClass)

See examples in `./envs` directory.

## Scripts

All scripts expects the path to a valid environment configuration file as single parameter:
```
$ <command> <path-to-conf-file>
```

Some scripts may take a while, up to 30-45 minutes for creating or destroying the infrastructure.

Commands waits until the operation is complete. Unfortunately, AWS CLI provides no simple way of showing whether it is waiting or is dead.

**TODO** Create a script waiting for a specific operation on a stack, in case the main scripts time-out

#### Commands

- `apply-infra.sh <config-file>`: Create/Update all resources except the DNS record in the custom domain. When the infra is ready the website is reachable throght the CloudFront endpoint, but the SSL certificate will not be valid. Use `show-infra` to show details about an active environment like the domain and buckets.
- `add-dns-record.sh <config-file>`: Requires the Infra stack of the environment up and ready. Creates the DNS record in the Route53 Hosted Zone pointing to the CloudFront distribution
- `show-infra.sh <config-file>`: Shows Outputs of the infra Stack: DNS name, bucket names etc
- `drop-all-contents.sh <config-file>`: Delete all contents in all buckets. **Cannot be undone**.
- `remove-dns-record.sh <config-file>`: Remove the DNS record pointing to CloudFront Distirbution, but  doesn't touch the infrastructure
- `remove-infra.sh <config-file>`: Completely remove the infrastructure. If bucket still contains anything removal will fail. Use `drop-all-contents` before removing. 


## A/B Testing

**TBD**

## Useful AWS CLI commands

### List SSL Certificates

```
$ aws acm list-certificates --region us-east-1 --query 'CertificateSummaryList[*].{Domains:DomainName,ARN:CertificateArn}' --output text
```

Shows certificates loaded in `us-east-1` and available to CloudFront.