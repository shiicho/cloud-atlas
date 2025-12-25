# Terraform CI/CD Demo

> **Hands-on Lab**: Experience a real GitHub Actions CI/CD pipeline for Terraform

This folder is a complete, ready-to-use template. Copy it to a new location, initialize as a Git repo, and push to GitHub to experience:

- **Plan on PR**: Automatic `terraform plan` with results posted as PR comments
- **Apply on Merge**: Automatic `terraform apply` with approval gate
- **OIDC Authentication**: No AWS access keys needed

---

## Prerequisites

Before starting, ensure you have:

- [ ] GitHub account
- [ ] AWS account with admin access
- [ ] AWS CLI configured (`aws sts get-caller-identity` works)
- [ ] Git installed
- [ ] Course repo cloned (`~/cloud-atlas/` exists)

> **没有课程代码？** Run `sync-course` on the lab instance, or see [lab-setup.md](../00-concepts/lab-setup.md)

---

## Lab Steps

### Step 1: Copy Template (3 min)

Copy this folder to a new location outside the course repo:

```bash
# On your lab instance (EC2 or local)
cp -r ~/cloud-atlas/iac/terraform/11-cicd/terraform-cicd-demo ~/my-terraform-cicd
cd ~/my-terraform-cicd

# Verify all files exist
ls -la
ls -la .github/workflows/
```

**Checkpoint**: You should see `main.tf`, `providers.tf`, and `.github/workflows/` folder.

---

### Step 2: Initialize Git (3 min)

Initialize this folder as a new Git repository:

```bash
git init
git add .
git commit -m "Initial commit: Terraform CI/CD demo"
```

**Checkpoint**: `git log` shows your initial commit.

---

### Step 3: Create GitHub Repository (5 min)

1. Go to [github.com/new](https://github.com/new)
2. Repository name: `my-terraform-cicd`
3. **Private** (or Public - your choice)
4. **DO NOT** check "Add a README file" (we already have one)
5. Click **Create repository**

After creating, connect your local repo:

```bash
# Replace YOUR_USERNAME with your GitHub username
git remote add origin https://github.com/YOUR_USERNAME/my-terraform-cicd.git
git branch -M main
git push -u origin main
```

**Checkpoint**: Refresh GitHub page - you should see all files including `.github/workflows/`.

---

### Step 4: Deploy OIDC Infrastructure (10 min)

OIDC allows GitHub Actions to authenticate with AWS without storing access keys.

```bash
cd ~/my-terraform-cicd/oidc-setup

# Deploy the CloudFormation stack
# Replace YOUR_USERNAME with your GitHub username
aws cloudformation deploy \
  --template-file github-oidc.yaml \
  --stack-name github-oidc-terraform \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    GitHubOrg=YOUR_USERNAME \
    RepoName=my-terraform-cicd

# Get the Role ARN (copy this for next step)
aws cloudformation describe-stacks \
  --stack-name github-oidc-terraform \
  --query 'Stacks[0].Outputs[?OutputKey==`RoleArn`].OutputValue' \
  --output text
```

**Checkpoint**: You should see an ARN like `arn:aws:iam::123456789012:role/github-actions-my-terraform-cicd`

---

### Step 5: Configure GitHub Secret (3 min)

Add the Role ARN as a GitHub secret:

1. Go to your GitHub repo
2. **Settings** > **Secrets and variables** > **Actions**
3. Click **New repository secret**
4. Name: `AWS_ROLE_ARN`
5. Value: (paste the Role ARN from Step 4)
6. Click **Add secret**

**Checkpoint**: Secrets page shows `AWS_ROLE_ARN` configured.

---

### Step 6: Enable GitHub Actions (2 min)

1. Go to **Actions** tab in your repo
2. If prompted, click **"I understand my workflows, go ahead and enable them"**

**Checkpoint**: You should see "Terraform Plan" and "Terraform Apply" workflows listed.

---

### Step 7: Configure Production Environment (5 min)

Set up an approval gate for the Apply workflow:

1. Go to **Settings** > **Environments**
2. Click **New environment**
3. Name: `production`
4. Click **Configure environment**
5. Under "Deployment protection rules", enable **Required reviewers**
6. Add yourself as a reviewer
7. Click **Save protection rules**

**Checkpoint**: Environment page shows "1 reviewer required".

> **Japan IT Context**: This is the **approval flow (承認フロー)** used in production deployments.

---

### Step 8: Create Feature Branch (3 min)

Now let's trigger the CI/CD pipeline by making a change:

```bash
cd ~/my-terraform-cicd

# Create a feature branch
git checkout -b feature/add-my-tag
```

Edit `main.tf` and add your custom tag in the tags block:

```hcl
  tags = {
    Name        = "CI/CD Demo Bucket"
    Environment = var.environment
    # Add this line:
    MyName = "your-name-here"
  }
```

Commit and push:

```bash
git add main.tf
git commit -m "feat: add MyName tag"
git push -u origin feature/add-my-tag
```

**Checkpoint**: Branch visible on GitHub.

---

### Step 9: Create Pull Request (5 min)

1. Go to your GitHub repo
2. You should see a banner: "feature/add-my-tag had recent pushes"
3. Click **Compare & pull request**
4. Title: "Add MyName tag"
5. Click **Create pull request**

**Checkpoint**: PR created, and "Terraform Plan" workflow starts automatically!

---

### Step 10: Review Plan Comment (5 min)

Wait for the workflow to complete (1-2 minutes), then:

1. Check the **Actions** tab - "Terraform Plan" should show green checkmark
2. Return to your PR
3. You should see a **bot comment** with the plan results:
   - Format check status
   - Init status
   - Validate status
   - Plan output (showing your new tag!)

**Checkpoint**: PR has a comment showing `+ MyName = "your-name-here"` in the plan.

> **This is the power of CI/CD**: Every change is reviewed before applying!

---

### Step 11: Merge and Observe Apply (5 min)

1. Click **Merge pull request** > **Confirm merge**
2. Go to **Actions** tab
3. You'll see "Terraform Apply" workflow triggered
4. The workflow **pauses** waiting for approval

Approve the deployment:

1. Click the workflow run
2. Click **Review deployments**
3. Check **production**
4. Click **Approve and deploy**

**Checkpoint**: Apply workflow completes with green checkmark.

> **Japan IT Context**: This is **production approval (本番承認)** - changes only apply after human review.

---

### Step 12: Verify Resources (3 min)

Verify the S3 bucket was created with your tag:

```bash
# List buckets matching our pattern
aws s3api list-buckets --query "Buckets[?contains(Name, 'cicd-demo')]" --output table

# Get the bucket name from the output, then check tags
aws s3api get-bucket-tagging --bucket cicd-demo-XXXXXXXX
```

**Checkpoint**: You should see your `MyName` tag in the output!

---

### Step 13: Cleanup (5 min)

When done, clean up all resources:

```bash
# Make sure AWS credentials are configured locally
aws sts get-caller-identity

# Go to your demo folder
cd ~/my-terraform-cicd

# Destroy Terraform resources (S3 bucket)
terraform init
terraform destroy -auto-approve

# Delete the OIDC CloudFormation stack
aws cloudformation delete-stack --stack-name github-oidc-terraform

# Wait for stack deletion
aws cloudformation wait stack-delete-complete --stack-name github-oidc-terraform

# Confirm cleanup
aws iam list-open-id-connect-providers
```

Optionally delete the GitHub repository:

1. Go to **Settings** > scroll to **Danger Zone**
2. Click **Delete this repository**
3. Confirm deletion

**Checkpoint**: All cloud resources removed, no ongoing costs.

---

## What You Learned

- **OIDC Authentication**: Secure, keyless authentication for CI/CD
- **Plan on PR**: Every change is previewed before applying
- **Approval Gate**: Human approval required for production changes
- **Full Automation**: No manual `terraform apply` needed

---

## Troubleshooting

### Workflow not triggering?

- Check Actions tab is enabled
- Verify `.github/workflows/` folder was pushed

### OIDC authentication failed?

- Verify `AWS_ROLE_ARN` secret is set correctly
- Check CloudFormation stack deployed successfully
- Ensure repo name matches exactly (case-sensitive)

### Plan shows errors?

- Check AWS credentials are working
- Verify the IAM role has required permissions

---

## Next Steps

- Try modifying `main.tf` again to see the full cycle
- Explore adding Infracost for cost visibility
- Implement branch protection rules
