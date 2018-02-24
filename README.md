# Website infrastructure provisioning

Create a single environment for hosting a static website on S3, served by CloudFront CDN on https with a custom DNS domain.

It also provides optional support for A/B testing.

The environment is defined in a configuration file.

Bash scripts allows to create/update the infrastructure, enable/disable the custom DNS record pointing the website, enable/disable A/B testing.

CloudFormation is used to manage infrastructurte

## Prerequisites

To provision a website infrastructure you need:

### AWS resources prerequisites

- A valid SSL certificate in ACM *Region us-east-1* for the custom domain. Certificates is loaded in any other reagion are not available to CloudFront
- A custom DNS Zone hosted on Route53. The website DNS record will be added (may be a sub-domain or APEX)

### Control machine prerequisites

On the machine running these scripts you need:

- AWS CLI
- Credentials of an AWS use with permissions to manage S3 buckets, CloudFront, Route53, Lambda and using CloudFormation

To build and deploy Lambda functions for A/B testing you also need:
- Node.js v6.5.0 or later
- Serverless Node tooling installed globally [see documentation](https://serverless.com/framework/docs/providers/aws/guide/installation/)

You don't need Node or Serverless if you are not going to use A/B testing.


Scripts expect AWS CLI to be configured, either with `aws configure` or setting  `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` env variables.

The AWS Region is defined in the environment configuration file (see below) so the default Region is irrelevant, so `AWS_DEFAULT_REGION` (or `aws configure`d Default Region) is not required and will be ignored.


## Description of the infrastructure

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
- A/B testing uses a single Lambda function, deployed and attached to the CloudFront Distribution as *Origin Request* handler.

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
Sample config files are available in `./config`.

It defines the CloudFormation stack name prefix and names of resources to be created.

A configuration file must define all the following variables:

- `ENV_NAME`: Name if the environment used as base name for the CloudFormation stacks. Alphanumeric an hyphens only.
- `RESOURCES_REGION`: All S3 buckets and CloudFormation template go into this Region. Other resources are global or are always deployed in `us-east-1`
- `SITE_BUCKET`: Name of the S3 bucket that will host the (main version of) the website. Must be a valid S3 bucket name (globally unique, valid DNS name)
- `LOGS_BUCKET` (optional): Name of the bucket that will store CloudFront logs. Must be a valid S3 bucket name (globally unique, valid DNS name)

- `WEBISTE_DNS_NAME`: FQ DNS name of the website. Must be in the specified domain, but may be the APEX
- `WEBSITE_DOMAIN`: Route53 Hosted Zone
- `CERTIFICATE_ARN`: ARN of an SSL certificate already loaded in ACM **`us-east-1` Region**, for the website DNS name
- `CDN_PRICE_CLASS` ('PriceClass_All', 'PriceClass_200' or 'PriceClass_100'): CloudFront CDN price class. See [CloudFront API Reference](https://docs.aws.amazon.com/cloudfront/latest/APIReference/API_CreateDistribution.html#cloudfront-CreateDistribution-request-PriceClass)

### CloudFormation stack names

Names of the CloudFormation stacks are derived from `ENV_NAME`.

- Infrastructure stack: *website-infra-<ENV_NAME>* (in Region `RESOURCES_REGION`)
- DNS stack: *website-dns-<ENV_NAME>*  (in Region `RESOURCES_REGION`)
- A/B testing Lambda stack: *website-lambda-<ENV_NAME> (in Region `us-east-1`)

No naming is enforced for S3 buckets, but it is advisable to keep them consistent stacks naming. 

## Scripts

All scripts expects the path to a valid environment configuration file as single parameter:
```
$ <command> <path-to-conf-file>
```

Some scripts may take a while, up to 30-45 minutes for creating or destroying the infrastructure.

Commands waits until the operation is complete. Unfortunately, AWS CLI provides no simple way of showing whether it is waiting or is dead.


- `apply-infra.sh <config-file>`: Create/Update all resources except the DNS record in the custom domain. When the infra is ready the website is reachable throght the CloudFront endpoint, but the SSL certificate will not be valid. Use `show-infra` to show details about an active environment like the domain and buckets.
- `add-dns-record.sh <config-file>`: Requires the Infra stack of the environment up and ready. Creates the DNS record in the Route53 Hosted Zone pointing to the CloudFront distribution
- `delete-all-contents.sh <config-file>`: Delete all contents in all buckets. **Cannot be undone**.
- `remove-dns-record.sh <config-file>`: Remove the DNS record pointing to CloudFront Distirbution, but  doesn't touch the infrastructure
- `remove-infra.sh <config-file>`: Completely remove the infrastructure. If bucket still contains anything removal will fail. Use `delete-all-contents` before removing. 

Other scripts:
- `show-status.sh <config-file>`: Show status and outputs of all stacks
- `invalidate-cache.sh <config-file>`: Invalidate CloudFront Distibution cache

### Adding DNS record

The DNS record is handled separately from the infrastructure to allow switching real traffic later, when everything is set up and tested.

Without the DNS record the website is still accessible at the CloudFront endpoint (also via https).


## A/B Testing

To have the ability to enable A/B testing on the website, you must specify an additional parameter in the configuration file:
- `AB_EXPERIMENT_BUCKET` (optional) Name of the S3 bucket that will host the A/B testing experiment version of the webiste. If omitted, A/B testing will not be available. Must be a valid S3 bucket name (globally unique, valid DNS name)

This will create an additional bucket used only when A/B testing is enabled.

### Enabling A/B testing

The environment must have an *Experiment* bucket to enable A/B testing.
Experimental content must be loaded into the bucket before enabling it.

```
$ enable-ab-testing.sh <config-file>
```

This creates a Lambda function and attaches it to the CloudFront Distribution.
When the modification is changed, CloudFront serves either versions randomly, 50-50%.

The version served is stable for the user session, using `X-Source` cookie.

Enabling A/B testing does three things:
1. Deploy the Lambda function after replacing the name and region of the experiment bucket in the code (Lamba@Edge canno have parameters). If the lambda already exists it creates a new numbered version.
2. Modify the CloudFront Distribution attaching the function to the Origin Request event. This may take a while to propagate, as any change to a Distribution
3. Invalidate CloudFront Distribution cache

### Disabling A/B testing

```
$ disable-ab-testing.sh <config-file>
```

Disabling A/B testing does two things:
1. Modify the CloudFront Distribution detaching the function (...takes a while)
2. Invalidate Distribution cache

Disabling A/B testing **does not** remove the Lambda function, due to an intrinsic limitation of Lambda@Edge.
Any function that has been attached to a Distribution cannot be immediately deleted after being detached.
The function get removed from the CDN replica with a very-eventually consistent process that cannot be monitored and may take hours.

Anyhow, a deployed but unused Lambda function does not cost anything. It will be overwritten when you enable A/B testing again.


## Known issues

### Do not use newly created S3 buckets immediately

There is a [known issue](https://forums.aws.amazon.com/thread.jspa?threadID=216814) when CloudFront serves content from a brand new S3 bucket. 
Client request may be temporarely redirected to the bucket causing an error.
This is caused by incomplete replication of the bucket.

When you create a brand new environment, wait a while before redirecting any real traffic to it.

If you try to access the content too early you get redirected to `https://website-<env>.site.s3-<region>.amazonaws.com/index.html`.
The browser complains the SSL certificate is not validate, but even if you bypass validation you get an *Access Denied* error, as the bucket is not directly accessible.

Unfortunately, there is no AWS CLI command to signal when the bucket is settled down.
Just try until it works.
It may take tenths of minutes.


### Error whan "No change is requried"

If you run `apply-infra.sh` when no actual change is requried, CloudFormation explodes with an error:
```
An error occurred (ValidationError) when calling the UpdateStack operation: No updates are to be performed.
Failed update-stack of website-justatest-infra stack.
```
This CloudFormation behaviour is utterly stupid!
AFAIK there is no way of having CloudFormation gently telling you "no change required" nor the AWS CLI returns a specific status for this error. So there is no easy way of intercepting this condition and exiting gently (maybe grepping stdout but... :facepalm:)

### Stack stuck in `ROLLBACK_FAILED`

If the CloudFormation stack ends up in `ROLLBACK_FAILED` there is no other way than deleting the stack with `remove-infra.sh` and retry. 
The only drawback is it is not deleted when you remove the infrastructure.

## Useful AWS CLI commands

### List SSL Certificates

```
$ aws acm list-certificates --region us-east-1 --query 'CertificateSummaryList[*].{Domains:DomainName,ARN:CertificateArn}' --output text
```

Shows certificates loaded in `us-east-1` and available to CloudFront.