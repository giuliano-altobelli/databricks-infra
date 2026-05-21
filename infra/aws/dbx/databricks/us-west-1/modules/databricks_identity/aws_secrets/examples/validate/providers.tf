provider "aws" {
  region = "us-west-1"
}

provider "aws" {
  alias  = "us_west_1"
  region = "us-west-1"
}
