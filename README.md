# Website infrastructure provisioning

Create a single environment for hosting a static website on S3, served by CloudFront CDN on https with a custom DNS domain.

It also provides optional support for A/B testing.

The environment is defined in a configuration file.

Bash scripts allows to create/update the infrastructure, enable/disable the custom DNS record pointing the website, enable/disable A/B testing.

CloudFormation is used to manage AWS Resources.

## Prerequisites

### AWS resources prerequisites

- A valid SSL certificate in ACM *Region us-east-1* for the custom domain. Certificates is loaded in any other reagion are not available to CloudFront
- A custom DNS Zone hosted on Route53. The website DNS record will be added (may be a sub-domain or APEX). The Route53 Zone must be in the same AWS account used for the website.

### Control machine prerequisites

On the machine running these scripts you need:

- AWS CLI installed
- Credentials of an AWS user with permissions to manage S3 buckets, CloudFront, Route53, Lambda and using CloudFormation

To build and deploy Lambda functions for A/B testing you also need:
- Node.js v6.5.0 or later
- Serverless.com installed globally [see documentation](https://serverless.com/framework/docs/providers/aws/guide/installation/)

You don't need Node or Serverless if you are not going to use A/B testing.


Scripts expect AWS CLI credentials either with `aws configure` or setting  `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` env variables.

The AWS Region is defined in the environment configuration file (see below). Any default Region is irrelevant ( `AWS_DEFAULT_REGION` or `aws configure`d Default Region are ignored).


## Description of the infrastructure

- CloudFront Distribution
    - Default behaviour pointing to *main* Origin, an S3 bucket
    - Distribution is https only (http redirects to https)
    - Custom domain, hosted on Route53
    - A valid SSL certificate is required for https on the custom domain
- Optionaly, creates a second *experiment* Origin for A/B testing
- A S3 bucket hosts website content (*main*)
    - Static Website Hosting is on
    - CloudFront uses "Custom Origin" (as opposed to "S3 Origin") to access the bucket
- A second, optional S3 bucket for *experiment* website, if you plan to use A/B testing
    - When A/B testing is not enabled the content of this bucket is ignored
- Another optional S3 bucket for CloudFront logs
- A DNS record (an *Alias* Route53 record) pointing to the CloudFront Distribution endpoint. 
    - The Zone must be hosted under the same AWS account
    - The Hostname may be any subdomain of and Hosted Zone, including the APEX (root). 
    - The DNS record is created with a separate operation. This allows switching the traffic when everything is set up and settled down.
- A/B testing uses a single Lambda function, deployed and attached to the CloudFront Distribution as *Origin Request* handler.
    - A/B testing is enabled/disabled with a separate operation, when required

## Provision infrastructure for a single environment

A configuration file defines a single website environment (e.g. "Production" or "Staging").

Bash scripts contol infrastructure provisioning and configuration.
The actual provisioning is controlled by CloudFormation, asynchronously, but scripts wait until changes are completed (or failed).

## Environment configuration file

An environment config file completely defines one environment of one website.

Sample config files are available in `./config`.

A configuration file must define all the following:

- `ENV_NAME`: Name if the environment used as base name for the CloudFormation stacks. Alphanumeric an hyphens only.
- `RESOURCES_REGION`: All S3 buckets and CloudFormation template go into this Region. Other resources are global or are always deployed in `us-east-1`
- `SITE_BUCKET`: Name of the S3 bucket that will host the (main version of) the website. Must be a valid S3 bucket name (globally unique, valid DNS name)
- `LOGS_BUCKET` (optional): Name of the bucket that will store CloudFront logs. Must be a valid S3 bucket name (globally unique, valid DNS name)
- `WEBISTE_DNS_NAME`: FQ DNS name of the website. Must be in the specified domain, but may be the APEX
- `WEBSITE_DOMAIN`: Route53 Hosted Zone
- `CERTIFICATE_ARN`: ARN of an SSL certificate already loaded in ACM **`us-east-1` Region**, for the website DNS name
- `CDN_PRICE_CLASS` ('PriceClass_All', 'PriceClass_200' or 'PriceClass_100'): CloudFront CDN price class. See [CloudFront API Reference](https://docs.aws.amazon.com/cloudfront/latest/APIReference/API_CreateDistribution.html#cloudfront-CreateDistribution-request-PriceClass)

A configuration file is bound to a single webiste instance, globally (you cannot reuse the same configuration in another Region or AWS account).

### CloudFormation stack names

Names of the CloudFormation stacks are derived from `ENV_NAME`.

- Infrastructure stack: *website-infra-<ENV_NAME>* (in Region `RESOURCES_REGION`)
- DNS stack: *website-dns-<ENV_NAME>*  (in Region `RESOURCES_REGION`)
- A/B testing Lambda stack: *website-lambda-<ENV_NAME> (in Region `us-east-1`)

CloudFormation Stack names must be unique in a AWS Account and Region. 

S3 bucket names must be globally unique across AWS.


## Scripts

All commands expects the path to a valid environment configuration file as single parameter: `<command> <path-to-conf-file>`

e.g.
```
$ ./apply-infra.sh config/justatest.conf
```

Some of the scripts take a while to complete (30-60 mins), as they modify CDN configuration and wait for the change to propagate (unfortunately, AWS CLI provides no simple way of showing whether it is waiting or is dead. So commands freeze until completed or failed).

Commands:
- `apply-infra.sh <config-file>`: Create/Update all resources except the DNS record. When the infra is ready the website is reachable throght the CloudFront endpoint. 
- `add-dns-record.sh <config-file>`: Requires an up-and-ready Infra stack. Creates a DNS record in the Route53 Hosted Zone pointing to the CloudFront distribution.
- `delete-all-contents.sh <config-file>`: Clears all buckets, including logs.
- `remove-dns-record.sh <config-file>`: Remove the DNS record pointing to CloudFront Distirbution, but  doesn't touch the infrastructure.
- `remove-infra.sh <config-file>`: Completely remove the infrastructure. If any bucket contains any content (including the loging bucket) removal will fail. Use `delete-all-contents.sh` to get rid of them, before removing the infra. 

Other scripts:
- `show-status.sh <config-file>`: Show status and outputs of all stacks
- `invalidate-cache.sh <config-file>`: Invalidate CloudFront Distibution cache

### Adding DNS record

The DNS record is handled separately from the infrastructure, to allow switching real traffic when everything is set up, distributed and tested.

Without the DNS record the website is accessible from the CloudFront endpoint (https).


## A/B Testing

`AB_EXPERIMENT_BUCKET` must be defined in the configuration file, to be able to switch A/B testing on.
This creates an additional bucket to host an experimental version of the website. This content is not served when A/B testing is switched off.

The experimental version of the website must be loaded into the *Experiment* bucket before turning A/B testing on.

### Enabling A/B testing

```
$ enable-ab-testing.sh <config-file>
```

This creates a Lambda function and attaches it to the CloudFront Distribution.

When the CDN modification is completely propagated, CloudFront serves either versions randomly, 50-50%.

The version served to a client is kept stable for the duration of a session, using a cookie (`X-Source`).

Enabling A/B testing does three things:
1. Deploys the Lambda function after replacing the name and region of the experiment bucket in the code (Lamba@Edge cannot use env parameters). If the function already exists, it overwrites it and publish a new numbered versions.
2. Modifies the CloudFront Distribution attaching the function to the Origin Request event. This takes a while to propagate, as any change to a Distribution
3. Invalidate CloudFront Distribution cache

### Disabling A/B testing

```
$ disable-ab-testing.sh <config-file>
```

Disabling A/B testing does two things:
1. Modifies the CloudFront Distribution detaching the function (...takes a while)
2. Invalidates Distribution cache

When A/B testing is turned off, the `X-Source` cookie is ignored and the website version in *Main* bucket is served by default.

Disabling A/B testing **does not** remove the Lambda function, due to an intrinsic limitation of Lambda@Edge.
Any function that has been attached to a Distribution cannot be immediately deleted after being detached.
The function CDN replica are dropped very asynchronous process that cannot be monitored and may take hours.

Anyhow, a deployed but unused Lambda function if free. It will be overwritten when you enable A/B testing again.


## Known issues

### Do not immediately serve real (production) content from a newly created S3 bucket

There is a [known issue](https://forums.aws.amazon.com/thread.jspa?threadID=216814) when CloudFront serves content from a brand new S3 bucket. 
Client requests may be temporarely redirected to the bucket endpoint, causing an error.
This is due to an incomplete replication of the bucket across Regions.

When you create a brand new environment, wait a while before redirecting any real traffic to it.

If you try to access the content too early you get redirected to `https://website-<env>.site.s3-<region>.amazonaws.com/index.html`.
The browser complains the SSL certificate is not validate, but even if you bypass validation you get an *Access Denied* error, as the bucket is not directly accessible.

Unfortunately, there is no AWS CLI command to signal when the bucket is settled down.
Just try until it works.
It may take tenths of minutes.


### CloudFormation error when "No change is requried"

If you run `apply-infra.sh` when no actual change is requried, CloudFormation explodes with an error:
```
An error occurred (ValidationError) when calling the UpdateStack operation: No updates are to be performed.
Failed update-stack of website-justatest-infra stack.
```

This CloudFormation behaviour is utterly stupid but unavoidable.
AFAIK there is no way of having CloudFormation gently telling you "no change required" nor the AWS CLI returns a specific status for this error. No easy way of intercepting this condition and exiting gently (maybe grepping stdout but... :facepalm:)

### CloudFormation Stack stuck in `ROLLBACK_FAILED`

If the CloudFormation stack ends up in `ROLLBACK_FAILED` there is no other way than deleting the stack with `remove-infra.sh` and retry. 

## Useful AWS CLI commands

### List SSL Certificates

```
$ aws acm list-certificates --region us-east-1 --query 'CertificateSummaryList[*].{Domains:DomainName,ARN:CertificateArn}' --output text
```

Shows certificates loaded in `us-east-1` and available to CloudFront.
