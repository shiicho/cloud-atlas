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
- [ ] **GitHub Personal Access Token (PAT)** with `repo` + `workflow` scopes — [Create one here](https://github.com/settings/tokens/new?scopes=repo,workflow)
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

### Step 2: Configure S3 Remote Backend (5 min)

The demo uses S3 remote backend for state storage. This is **critical** for CI/CD because:
- State persists across GitHub Actions runs (runners are ephemeral)
- State locking prevents concurrent apply conflicts
- Cleanup via `terraform destroy` actually works!

**Get your S3 bucket name** from the terraform-lab CloudFormation stack:

```bash
# Get the bucket name created during course setup
BUCKET=$(aws cloudformation describe-stacks \
  --stack-name terraform-lab \
  --query 'Stacks[0].Outputs[?OutputKey==`TfStateBucketName`].OutputValue' \
  --output text)

echo "Your state bucket: $BUCKET"
```

> **没有 terraform-lab stack？** Deploy it first: [lab-setup.md](../00-concepts/lab-setup.md)

**Update backend.tf** with your bucket name:

```bash
cd ~/my-terraform-cicd

# Replace PLACEHOLDER with your actual bucket name
sed -i "s/PLACEHOLDER/$BUCKET/" backend.tf

# Verify the change
cat backend.tf
```

You should see your bucket name in the configuration:

```hcl
terraform {
  backend "s3" {
    bucket       = "tfstate-terraform-course-123456789012"  # Your bucket
    key          = "iac/terraform/11-cicd/cicd-demo/terraform.tfstate"
    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true
  }
}
```

**Checkpoint**: `backend.tf` shows your actual bucket name (not PLACEHOLDER).

---

### Step 3: Initialize Git (3 min)

Initialize this folder as a new Git repository:

```bash
git init
git add .
git commit -m "Initial commit: Terraform CI/CD demo"
```

**Checkpoint**: `git log` shows your initial commit.

---

### Step 4: Create GitHub Repository (5 min)

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
```

**Configure Git authentication** (first time only):

GitHub no longer accepts passwords for HTTPS git operations. You need a Personal Access Token (PAT):

<details>
<summary><strong>📋 How to create a GitHub PAT (click to expand)</strong></summary>

1. Go to [GitHub Settings → Developer settings → Personal access tokens → Tokens (classic)](https://github.com/settings/tokens/new?scopes=repo,workflow)
2. Click **"Generate new token"** → **"Generate new token (classic)"**
3. Fill in:
   - **Note**: `terraform-cicd-demo` (or any description)
   - **Expiration**: 30 days (or your preference)
   - **Select scopes**: Check both:
     - **`repo`** (Full control of private repositories)
     - **`workflow`** (Update GitHub Action workflows) ← Required for `.github/workflows/`
4. Click **"Generate token"**
5. **⚠️ Copy the token immediately** - you won't see it again!

</details>

```bash
# Store credentials (will prompt once, then remember)
git config --global credential.helper store

# Now push - when prompted:
#   Username: your GitHub username
#   Password: paste your PAT (not your GitHub password!)
git push -u origin main
```

> **💡 Tip**: If you have [GitHub CLI](https://cli.github.com/) installed, you can run `gh auth login` for easier setup.

**Checkpoint**: Refresh GitHub page - you should see all files including `.github/workflows/`.

---

### Step 5: Deploy OIDC Infrastructure (10 min)

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

### Step 6: Configure GitHub Secret (3 min)

Add the Role ARN as a GitHub secret:

1. Go to your GitHub repo
2. **Settings** > **Secrets and variables** > **Actions**
3. Click **New repository secret**
4. Name: `AWS_ROLE_ARN`
5. Value: (paste the Role ARN from Step 4)
6. Click **Add secret**

**Checkpoint**: Secrets page shows `AWS_ROLE_ARN` configured.

---

### Step 7: Enable GitHub Actions (2 min)

1. Go to **Actions** tab in your repo
2. If prompted, click **"I understand my workflows, go ahead and enable them"**

**Checkpoint**: You should see "Terraform Plan" and "Terraform Apply" workflows listed.

---

### Step 8: Configure Production Environment (5 min)

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

### Step 9: Create Feature Branch (3 min)

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

### Step 10: Create Pull Request (5 min)

1. Go to your GitHub repo
2. You should see a banner: "feature/add-my-tag had recent pushes"
3. Click **Compare & pull request**
4. Title: "Add MyName tag"
5. Click **Create pull request**

**Checkpoint**: PR created, and "Terraform Plan" workflow starts automatically!

---

### Step 11: Review Plan Comment (5 min)

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

### Step 12: Merge and Observe Apply (5 min)

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

### Step 13: Verify Resources (3 min)

Verify the S3 bucket was created with your tag:

```bash
# List buckets matching our pattern
aws s3api list-buckets --query "Buckets[?contains(Name, 'cicd-demo')]" --output table

# Get the bucket name from the output, then check tags
aws s3api get-bucket-tagging --bucket cicd-demo-XXXXXXXX
```

**Checkpoint**: You should see your `MyName` tag in the output!

---

### Step 14: Cleanup (10 min)

**Important**: Complete cleanup prevents orphan resources and credential leaks.

#### 14a. Destroy Terraform Resources

With S3 remote backend, `terraform destroy` works properly (state is persistent):

```bash
# Make sure AWS credentials are configured locally
aws sts get-caller-identity

# Go to your demo folder
cd ~/my-terraform-cicd

# Initialize Terraform (to connect to remote state)
terraform init

# Destroy all Terraform-managed resources
terraform destroy -auto-approve
```

**Checkpoint**: Output shows `Destroy complete! Resources: X destroyed.`

#### 14b. Delete OIDC CloudFormation Stack

```bash
# Delete the OIDC stack
aws cloudformation delete-stack --stack-name github-oidc-terraform

# Wait for stack deletion
aws cloudformation wait stack-delete-complete --stack-name github-oidc-terraform

# Confirm OIDC provider removed
aws iam list-open-id-connect-providers
```

#### 14c. Delete GitHub Repository

1. Go to your GitHub repo > **Settings**
2. Scroll to **Danger Zone** at bottom
3. Click **Delete this repository**
4. Type the repository name to confirm
5. Click **I understand the consequences, delete this repository**

#### 14d. Clean Up Git Credentials (Security)

The GitHub PAT you used is stored locally. Remove it:

```bash
# Remove stored credentials
# On Linux/macOS:
rm ~/.git-credentials 2>/dev/null || true

# Or selectively remove GitHub credentials:
git credential reject <<EOF
protocol=https
host=github.com
EOF

# Verify credentials removed
cat ~/.git-credentials 2>/dev/null || echo "Credentials file removed"
```

> **💡 Tip**: If you created a PAT specifically for this demo, also revoke it on GitHub:
> Settings > Developer settings > Personal access tokens > Delete the token

#### 14e. Clean Up Local Files

```bash
# Remove the demo folder
cd ~
rm -rf ~/my-terraform-cicd
```

**Checkpoint**: All resources cleaned up:
- [ ] Terraform resources destroyed (`terraform destroy`)
- [ ] CloudFormation OIDC stack deleted
- [ ] GitHub repository deleted
- [ ] Git credentials removed
- [ ] Local demo folder removed
- [ ] (Optional) PAT revoked on GitHub

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
