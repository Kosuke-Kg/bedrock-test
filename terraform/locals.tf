locals {
  # CIDR Block
  cidr_block = "10.0.0.0/16"

  # projectのタグ
  project_tag  = "project"
  project_name = "bedrock-test"

  # AZ設定
  availability_zones = ["ap-northeast-1a", "ap-northeast-1c", "ap-northeast-1d"]

  # サブネット設定
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}
