# Script to run manually on a new AWS EC2 instance
# Sets up everything including docker so we can then:
#     manually copy the docker-compose.yml from https://github.com/collective/training-deploy-project/blob/main/ansible/docker-compose.yml
#     manually run docker-compose
#     ensure that we clean up the shell command history
#     create an Amazon Machine Image (AMI) from this EC2 instance
#     release the new AMI as a community AMI with the approp
# After all that, we

apt-get -y install curl gpg git

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update

apt-get install docker-ce docker-ce-cli containerd.io

apt-get -y install docker-compose

usermod -a -G docker ubuntu

apt-get -y install nginx