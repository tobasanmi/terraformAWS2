#!/bin/bash
              sudo yum update -y
              sudo yum install docker -y
              sudo usermod -a -G docker ec2-user
              sudo systemctl start docker
              sudo docker run -d -p 3000:3000 -v ~/metabase-data:/metabase-data \
                -e "MB_DB_FILE=/metabase-data/metabase.db" \
                --name metabase metabase/metabase




# <<-EOF
#               #!/bin/bash
#               sudo yum update -y
#               sudo yum install docker -y
#               sudo usermod -a -G docker ec2-user
#               sudo systemctl start docker
#               sudo docker run -d -p 3000:3000 -v ~/metabase-data:/metabase-data \
#                 -e "MB_DB_FILE=/metabase-data/metabase.db" \
#                 --name metabase metabase/metabase
#               EOF