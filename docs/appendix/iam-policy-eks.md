# IAM Policy cho EKS Full Lifecycle

## Inline Policy cho IAM User `nt531-eks-admin`

Policy này cung cấp quyền tối thiểu cần thiết để Terraform tạo và quản lý EKS cluster.

> Thay `<ACCOUNT_ID>` bằng AWS Account ID thực tế. Nếu đổi `project_name`, cập nhật lại prefix role tương ứng (`nt531-bm*`).

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EKSClusterLifecycle",
      "Effect": "Allow",
      "Action": [
        "eks:CreateCluster",
        "eks:DescribeCluster",
        "eks:ListClusters",
        "eks:ListUpdates",
        "eks:DescribeUpdate",
        "eks:UpdateClusterConfig",
        "eks:UpdateClusterVersion",
        "eks:DeleteCluster",
        "eks:CreateNodegroup",
        "eks:DescribeNodegroup",
        "eks:ListNodegroups",
        "eks:UpdateNodegroupConfig",
        "eks:UpdateNodegroupVersion",
        "eks:DeleteNodegroup",
        "eks:DescribeAddonVersions",
        "eks:ListAddons",
        "eks:DescribeAddon",
        "eks:CreateAddon",
        "eks:UpdateAddon",
        "eks:DeleteAddon",
        "eks:CreateAccessEntry",
        "eks:DescribeAccessEntry",
        "eks:ListAccessEntries",
        "eks:UpdateAccessEntry",
        "eks:DeleteAccessEntry",
        "eks:AssociateAccessPolicy",
        "eks:DisassociateAccessPolicy",
        "eks:ListAssociatedAccessPolicies",
        "eks:TagResource",
        "eks:UntagResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "PassRoleForEKS",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::<ACCOUNT_ID>:role/nt531-bm*"
    }
  ]
}
```

## Các trường hợp cần thêm quyền

### Khi bật CloudWatch control-plane logs

```json
{
  "Sid": "CloudWatchLogs",
  "Effect": "Allow",
  "Action": [
    "logs:CreateLogGroup",
    "logs:PutRetentionPolicy",
    "logs:TagResource"
  ],
  "Resource": "*"
}
```

### Khi bật EKS secrets encryption bằng KMS key mới

```json
{
  "Sid": "KMSForSecretsEncryption",
  "Effect": "Allow",
  "Action": [
    "kms:CreateKey",
    "kms:TagResource",
    "kms:DescribeKey",
    "kms:CreateAlias"
  ],
  "Resource": "*"
}
```

## Cách attach policy

1. AWS Console → IAM → Users → `nt531-eks-admin`
2. Tab **Permissions** → **Add permissions** → **Create inline policy**
3. Chọn tab **JSON**, dán policy ở trên
4. **Review policy** → đặt tên (vd. `NT531-EKS-Lifecycle`) → **Create policy**
