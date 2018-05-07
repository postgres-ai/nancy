Requirements
---
You need to have Docker installed on your macos/linux/windows machine, with docker-machine included.
Also, AWS CLI tool set should be installed and configured on your machine to allow working with AWS ECS.

How to Build a Docker Image
---
Example of building a new image for EC2 instance type r4.large with Postgres 9.6:
```bash
cd ./docker
docker build --build-arg PG_VERSION=9.6 --build-arg AWS_EC2_TYPE=r4.large -t pg96exp_r4large .
```

Then tag it and push to ECS (https://aws.amazon.com/ecs/):
```bash
docker tag pg96exp_r4large:latest 950603059350.dkr.ecr.us-east-1.amazonaws.com/nancy:pg96_r4large
docker push 950603059350.dkr.ecr.us-east-1.amazonaws.com/nancy:pg96_r4large
```

How to Run a Spot EC2 Instance with Docker Container
---
To run an EC2 image, use `docker-machine` (see https://docs.docker.com/machine/) first (takes a few minutes):
```bash
export DOCKER_MACHINE=nancy-test-20180506
docker-machine create --driver=amazonec2 --amazonec2-request-spot-instance \
  --amazonec2-keypair-name=awskey --amazonec2-ssh-keypath=/Users/nikolay/.ssh/awskey.pem \
  --amazonec2-instance-type=r4.large --amazonec2-spot-price=0.0315 $DOCKER_MACHINE
```

Important: price used in this example might be too low – check EC2 web console, and if you see that spot instance
was not fulfilled, kill machine with `docker-machine rm -y $DOCKER_MACHINE` and create again, with slightly higher price.

And then deploy the prepared container:
```bash
eval $(docker-machine env $DOCKER_MACHINE)
docker `docker-machine config $DOCKER_MACHINE` run --name="pg_$DOCKER_MACHINE" \
  -dit 950603059350.dkr.ecr.us-east-1.amazonaws.com/nancy:pg96_r4large
```

Check container state:
```bash
docker `docker-machine config $DOCKER_MACHINE` ps
```

If everything is ok, you can run psql (this line will run psql inside container locally):
```bash
docker `docker-machine config $DOCKER_MACHINE` ps
```

