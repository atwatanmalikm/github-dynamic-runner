# github-dynamic-runner

Self spawned runner for github action on GCP

![Dynamic Runner Github](https://user-images.githubusercontent.com/34089274/178459756-0156eb39-10b8-4b11-a233-184b875f90af.jpg)

## Prerequisite:

1\. User runner
```bash
sudo adduser runner
echo "runner    ALL=(ALL:ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/runner
```

2\. Directory /mnt/runner
```bash
sudo mkdir /mnt/runner
sudo chown -R runner:runner /mnt/runner
```

3\. Worker image