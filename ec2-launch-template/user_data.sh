#!/bin/bash
dnf update -y
dnf install httpd -y
systemctl enable httpd
systemctl start httpd

TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/availability-zone)

cat > /var/www/html/index.html <<EOF2
<!DOCTYPE html>
<html>
<head>
  <title>CloudHER Auto Scaling Lab</title>
  <style>
    body { font-family: Arial, sans-serif; background:#f4f7fb; text-align:center; margin:0; }
    header { background:#232f3e; color:white; padding:50px; }
    .card { background:white; margin:40px auto; padding:30px; width:70%; border-radius:12px; box-shadow:0 4px 14px rgba(0,0,0,0.1); }
    .badge { background:#ff9900; padding:8px 16px; border-radius:20px; font-weight:bold; }
  </style>
</head>
<body>
  <header>
    <h1>CloudHER Week 6</h1>
    <h2>Auto Scaling Lab</h2>
  </header>
  <section class="card">
    <span class="badge">Running on EC2</span>
    <p><strong>Instance ID:</strong> $INSTANCE_ID</p>
    <p><strong>Availability Zone:</strong> $AZ</p>
    <p>This page was created automatically by Launch Template User Data.</p>
  </section>
</body>
</html>
EOF2