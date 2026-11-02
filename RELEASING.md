# Releasing Plone in a Box™

`tkimnguyen/plone-in-a-box` is where development happens. `collective/plone-in-a-box` is kept in sync after each
release, and the public Linode StackScript is updated by hand.

## 1. Make and test the changes

1. Work on a branch and open a pull request into `main`. CI (ShellCheck, `terraform fmt`, `terraform validate`,
   `cfn-lint`, and a check that the CloudFormation template is up to date) must pass. Whenever `src/StackScript` or
   `src/aws/cloudformation.in.yaml` changes, run `python3 scripts/build-cloudformation.py` and commit the regenerated
   `src/aws/cloudformation.yaml`.
2. Test the changed script before merging:
   * **Linode**: paste `src/StackScript` from the branch into the private test StackScript (`plone-in-a-box-test`,
     Target Image Ubuntu 24.04) and deploy a 2 GB Linode from it.
   * **AWS** (if `src/aws/` or the script changed): `terraform apply` from `src/aws/` on the branch.
   * **DigitalOcean** (if `src/digitalocean/` or the script changed): `terraform apply` from `src/digitalocean/`.
   * **AWS Launch Stack** (if the template or the script changed): upload the branch's `src/aws/cloudformation.yaml`
     to `s3://plone-in-a-box-templates/test/cloudformation.yaml` and create a stack from that URL in the
     CloudFormation console (**Create stack → With new resources → Amazon S3 URL**).
   * Checks on each test server:
     * right after creating the server, its address shows the setup progress page, which turns into the site
     * `/root/plone-credentials.txt` exists, the site loads, and `admin` can log in with the generated password
     * deploy once more with **Plone admin password** set: `admin` logs in with that password, and the credentials
       file doesn't contain it
     * `sudo plone-reset-admin-password` changes the password, and the new one works
     * from outside, ports 5432, 8080 and 3000 time out (`nc -zv -w 5 <ip> <port>`)
     * after `docker compose --project-directory /opt/plone up -d --force-recreate backend`, the same password
       still works
   * Delete the test servers afterwards (`terraform destroy` with the same `-var` options).
3. Merge the pull request.

## 2. Release

1. In `CHANGES.md`, replace `(unreleased)` with today's date, and commit to `main` (or include it in the last PR).
2. On GitHub, go to **Releases → Draft a new release**. Create a tag on `main` named after the version, without a
   `v` (for example `2.1`), set the title to `Plone in a Box 2.1`, and summarize the changes.

## 3. Publish the CloudFormation template

The **Launch Stack** button in the README opens
`https://plone-in-a-box-templates.s3.us-east-1.amazonaws.com/latest/cloudformation.yaml`. After each release, upload
`src/aws/cloudformation.yaml` from `main` twice, in the S3 console (bucket **plone-in-a-box-templates** → **Upload**)
or with the AWS CLI:

```
aws s3 cp src/aws/cloudformation.yaml s3://plone-in-a-box-templates/2.3/cloudformation.yaml
aws s3 cp src/aws/cloudformation.yaml s3://plone-in-a-box-templates/latest/cloudformation.yaml
```

(using the release's version number in the first path), then click the button to check it opens.

One-time setup of the bucket, in the S3 console, region **US East (N. Virginia) us-east-1**:

1. **Create bucket** named `plone-in-a-box-templates`. Under **Block Public Access settings**, untick **Block all
   public access** and confirm. Leave everything else as is.
2. Open the bucket → **Permissions → Bucket policy → Edit**, paste this, and save:
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [{
       "Sid": "PublicReadTemplates",
       "Effect": "Allow",
       "Principal": "*",
       "Action": "s3:GetObject",
       "Resource": "arn:aws:s3:::plone-in-a-box-templates/*"
     }]
   }
   ```
   Only put CloudFormation templates in this bucket: everything in it is public.

## 4. Update the public Linode StackScript

1. Log in to Cloud Manager as **nguyen-plone**, the account that owns the public **Plone in a Box** StackScript.
2. **StackScripts → Account StackScripts → ⋯ → Edit**.
3. Replace the **Script** with
   https://raw.githubusercontent.com/tkimnguyen/plone-in-a-box/main/src/StackScript, check that **Target Images**
   includes the Ubuntu release the script supports, and enter a revision note such as `2.1: <summary>`.
4. Save, then confirm the Community StackScripts list shows today's date.

Public StackScripts can't be deleted or made private by their owner; only Linode support can remove one.

## 5. Sync `collective/plone-in-a-box`

One-time setup on your machine:

```
git remote add collective git@github.com:collective/plone-in-a-box.git
```

After each release:

```
git checkout main && git pull
git push collective main:sync-from-tkimnguyen
```

Open https://github.com/collective/plone-in-a-box/compare/main...sync-from-tkimnguyen, create the pull request,
merge it once CI passes, and delete the `sync-from-tkimnguyen` branch.

Avoid committing directly to `collective`, so these pull requests stay simple fast-forwards. If someone does
contribute there, bring it into this repo first with `git pull collective main`.

Pushing needs an SSH key added to GitHub (`ssh -T git@github.com` should greet you by name). HTTPS pushes with a
password are rejected.
