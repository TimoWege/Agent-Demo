# Resource addresses were renamed from the author's personal timo1/timo2
# naming to generic instance1/instance2. These `moved` blocks let Terraform
# re-track existing state under the new address instead of destroying and
# recreating resources purely because of the renamed address.

moved {
  from = aws_instance.timo1
  to   = aws_instance.instance1
}

moved {
  from = aws_instance.timo2
  to   = aws_instance.instance2
}

moved {
  from = aws_iam_role.timo1_s3_read
  to   = aws_iam_role.instance1_s3_read
}

moved {
  from = aws_iam_role_policy.timo1_s3_read
  to   = aws_iam_role_policy.instance1_s3_read
}

moved {
  from = aws_iam_instance_profile.timo1_s3_read
  to   = aws_iam_instance_profile.instance1_s3_read
}

moved {
  from = local_file.connect_timo1
  to   = local_file.connect_instance1
}

moved {
  from = local_file.connect_timo2
  to   = local_file.connect_instance2
}
