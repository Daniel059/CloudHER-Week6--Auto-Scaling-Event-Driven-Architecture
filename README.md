# CloudHER Week 6 — AWS Auto Scaling & Event-Driven Architecture

A hands-on AWS learning project covering **EC2 Auto Scaling, Application Load Balancing, Multi-AZ architecture, health checks, IMDSv2, and event-driven computing with Lambda**.

> **Goal:** Build a web application that can automatically run across multiple EC2 instances, distribute traffic through an Application Load Balancer, and scale when demand increases.

---

## Architecture

```text
                         Internet
                            │
                            ▼
                 ┌─────────────────────┐
                 │ Application Load     │
                 │ Balancer :80         │
                 └──────────┬──────────┘
                            │
                     Target Group
                       /       \
                      /         \
                     ▼           ▼
              EC2 us-east-1a  EC2 us-east-1b
                    │              │
                    └──────┬───────┘
                           │
                    Auto Scaling Group
                           │
                    Launch Template
                           │
                    CloudWatch Scaling
```

The project is divided into:

- **Lab 1 — Auto Scaling:** EC2, Launch Template, Auto Scaling Group, Target Group, ALB and Multi-AZ deployment. ✅ **Complete**
- **Lab 2 — Event Driven:** Lambda + event-driven architecture  

  > 🚧 **Coming Soon** — The Lambda magic is still brewing in the cloud kitchen.  
  > Stay tuned… the event-driven side of this project is on its way and will land here shortly.  
  > (Spoiler: things are about to get reactive ⚡)

---

## Project Structure

```text
CLOUDHER-WEEK6-AUTOSCALING/
│
├── ec2-launch-template/
│   └── user_data.sh
│
├── lambda/                          ← Lab 2 (coming soon)
│
├── screenshots/
│   ├── lab1-autoscaling/
│   │   ├── 01a-alb-security-group.png
│   │   ├── 01b-ec2-security-group.png
│   │   ├── 02-launch-template.png
│   │   ├── 03-target-group.png
│   │   ├── 04-load-balancer.png
│   │   ├── 05-asg-config.png
│   │   ├── 06-ec2-instances-running.png
│   │   ├── 07-target-group-healthy.png
│   │   ├── 08a-alb-browser-test-1.png
│   │   └── 08a-alb-browser-test-2.png
│   │
│   └── lab2-eventdriven/            ← Screenshots landing soon
│
├── LICENSE
└── README.md
```

---

# Lab 1 — EC2 Auto Scaling & Load Balancing

**Step-by-Step Guide**  
Follow these steps **in order** to replicate this deployment.  
Each step’s screenshot sits right below it, so the evidence lines up with the activity that produced it.

---

### Step 1: Create the Security Groups

We create two separate security groups so traffic flows the right way:

- **ALB Security Group** → allows HTTP from the internet  
- **EC2 Security Group** → allows HTTP only from the ALB

#### 1.1 Create the ALB Security Group

1. Open the **EC2 Console → Security Groups → Create security group**.
2. **Name**: `CloudHER-ALB-SG`
3. **Description**: `Allow HTTP from the internet`
4. **VPC**: Select your default VPC (or the one you are using)
5. Under **Inbound rules** → **Add rule**:
   - Type: **HTTP**
   - Protocol: TCP
   - Port: **80**
   - Source: `0.0.0.0/0`
6. Leave **Outbound rules** as default → click **Create security group**

![ALB Security Group](screenshots/lab1-autoscaling/01a-alb-security-group.png)

#### 1.2 Create the EC2 Security Group

1. Still in **Security Groups → Create security group**
2. **Name**: `CloudHER-EC2-SG`
3. **Description**: `Allow HTTP only from the ALB`
4. **VPC**: Same VPC as above
5. Under **Inbound rules** → **Add rule**:
   - Type: **HTTP**
   - Protocol: TCP
   - Port: **80**
   - Source: Select the **CloudHER-ALB-SG** security group  
     (do **not** use `0.0.0.0/0`)
6. Leave **Outbound rules** as default → click **Create security group**

![EC2 Security Group](screenshots/lab1-autoscaling/01b-ec2-security-group.png)

**Why two security groups?**  
This creates the intended traffic path:

```text
Internet → ALB → EC2
```

instead of exposing the EC2 web servers directly to the internet.

---

### Step 2: Create the Launch Template

The Launch Template defines how every EC2 instance created by the Auto Scaling Group should be configured. This gives you **consistency**.

1. Open **EC2 Console → Launch Templates → Create launch template**
2. **Launch template name**: `CloudHER-Launch-Template`
3. **Template version description**: `v1 – Apache + IMDSv2`
4. Under **Application and OS Images (Amazon Machine Image)**:
   - Choose **Amazon Linux 2023**
5. **Instance type**: `t3.micro` (or `t2.micro`)
6. **Key pair** (optional for this lab): Select an existing key pair or continue without one
7. Under **Network settings**:
   - Security groups → Select **CloudHER-EC2-SG**
8. Expand **Advanced details** → find **User data**
9. Paste the contents of `ec2-launch-template/user_data.sh`  
   (or upload the file)
10. Leave everything else default → click **Create launch template**

![Launch Template](screenshots/lab1-autoscaling/02-launch-template.png)

**Tip:** When the Auto Scaling Group needs a new instance, AWS will use this exact configuration every time.

---

### Step 3: Understand the User Data Script (IMDSv2)

The User Data script runs automatically the first time an instance boots. It does the following:

1. Updates the system packages
2. Installs Apache (`httpd`)
3. Starts and enables Apache
4. Requests an **IMDSv2** session token
5. Uses that token to fetch the Instance ID and Availability Zone
6. Creates a simple HTML page that displays those values

Key part of the script (IMDSv2):

```bash
TOKEN=$(curl -sS -X PUT \
  "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")

INSTANCE_ID=$(curl -sS \
  -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)

AZ=$(curl -sS \
  -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)
```

**Why IMDSv2 matters:**  
Older scripts that call the metadata service without a token often return empty values. IMDSv2 is the secure, recommended method and is required in many AWS environments.

---

### Step 4: Create the Target Group

The Target Group is the pool of instances that the Load Balancer will send traffic to. It also performs health checks.

1. Open **EC2 Console → Target Groups → Create target group**
2. **Target type**: Instances
3. **Target group name**: `CloudHER-TG`
4. **Protocol**: HTTP  
   **Port**: 80
5. **VPC**: Same VPC used earlier
6. **Health check protocol**: HTTP
7. **Health check path**: `/`
8. Leave the remaining settings as default → click **Next**
9. On the “Register targets” page, do **not** register any instances yet  
   (the Auto Scaling Group will do this automatically) → click **Create target group**

![Target Group](screenshots/lab1-autoscaling/03-target-group.png)

Only healthy targets should receive traffic from the ALB.

---

### Step 5: Create the Application Load Balancer

The ALB is the public entry point for your application.

1. Open **EC2 Console → Load Balancers → Create load balancer**
2. Choose **Application Load Balancer**
3. **Name**: `CloudHER-ALB`
4. **Scheme**: Internet-facing
5. **IP address type**: IPv4
6. Under **Network mapping**:
   - Select at least **two Availability Zones** (for example `us-east-1a` and `us-east-1b`)
   - Choose a **public subnet** in each AZ
7. **Security groups**: Select **CloudHER-ALB-SG**
8. Under **Listeners and routing**:
   - Protocol: **HTTP**, Port: **80**
   - Default action: **Forward to** → select `CloudHER-TG`
9. Review the settings → click **Create load balancer**

![Application Load Balancer](screenshots/lab1-autoscaling/04-load-balancer.png)

**Resulting request path:**

```text
Browser
   ↓
Application Load Balancer
   ↓
Target Group
   ↓
Healthy EC2 Instance
```

---

### Step 6: Create the Auto Scaling Group

The Auto Scaling Group uses the Launch Template to maintain the desired number of EC2 instances and can scale when needed.

1. Open **EC2 Console → Auto Scaling Groups → Create Auto Scaling group**
2. **Name**: `CloudHER-ASG`
3. **Launch template**: Select `CloudHER-Launch-Template` (version 1)
4. Click **Next**
5. **VPC**: Same VPC
6. **Availability Zones and subnets**: Select the same two public subnets you used for the ALB (`us-east-1a` and `us-east-1b`)
7. Click **Next**
8. Under **Load balancing**:
   - Choose **Attach to an existing load balancer**
   - Select **Choose from your load balancer target groups**
   - Select `CloudHER-TG`
9. **Health check type**: Turn on **ELB** health checks (in addition to EC2)
10. Click **Next**
11. **Group size**:
    - Desired capacity: **2**
    - Minimum capacity: **2**
    - Maximum capacity: **4**
12. (Optional) Add a scaling policy later — for now you can skip it
13. Review everything → click **Create Auto Scaling group**

![Auto Scaling Group Configuration](screenshots/lab1-autoscaling/05-asg-config.png)

The ASG will now launch 2 instances across the two Availability Zones and automatically register them with the Target Group.

---

### Step 7: Verify the EC2 Instances

1. Go to **EC2 Console → Instances**
2. You should see two instances in the **running** state
3. Check the **Availability Zone** column — one should be in `us-east-1a` and the other in `us-east-1b`

Example (your Instance IDs will be different):

```text
i-0647d365c481e8008 → us-east-1a
i-093c25f1ba6f4be2e → us-east-1b
```

![EC2 Instances Running](screenshots/lab1-autoscaling/06-ec2-instances-running.png)

---

### Step 8: Verify Target Health

1. Go to **EC2 Console → Target Groups → CloudHER-TG → Targets** tab
2. Wait a few minutes for the health checks to complete
3. Both instances should eventually show status **Healthy**

This confirms that:

- Apache is running
- Port 80 is reachable
- The security groups allow the required traffic
- The Target Group health check is succeeding

![Healthy Target Group](screenshots/lab1-autoscaling/07-target-group-healthy.png)

---

### Step 9: Test Load Balancing

1. Go to **EC2 Console → Load Balancers → CloudHER-ALB**
2. Copy the **DNS name**
3. Open a browser and go to:

```text
http://<ALB-DNS-NAME>
```

4. The page should display the EC2 Instance ID and Availability Zone
5. **Refresh the page several times**

One request may return:

```text
Instance ID: i-0647d365c481e8008
Availability Zone: us-east-1a
```

while another can return:

```text
Instance ID: i-093c25f1ba6f4be2e
Availability Zone: us-east-1b
```

This proves that the ALB is distributing requests across the EC2 instances.

![ALB Browser Test — Instance 1](screenshots/lab1-autoscaling/08a-alb-browser-test-1.png)

![ALB Browser Test — Instance 2](screenshots/lab1-autoscaling/08a-alb-browser-test-2.png)

---

# Troubleshooting

## IMDSv2 Token Requirement

**Symptom:** The webpage loads, but the Instance ID and Availability Zone are blank.

**Cause:** The original metadata requests used the older IMDSv1-style approach:

```bash
curl http://169.254.169.254/latest/meta-data/instance-id
```

Many AWS environments now require **IMDSv2**, which needs a session token.

**Solution:**

```text
Request IMDSv2 token
        ↓
Pass token in metadata request
        ↓
Retrieve Instance ID / Availability Zone
        ↓
Generate webpage
```

**Lesson:** A web server can be healthy while the application configuration running on it is still incorrect. Troubleshoot each layer separately.

---

## Public IP and Networking Issue

If an instance does not behave as expected for public connectivity, check the full network path:

```text
VPC
 ↓
Subnet
 ↓
Route Table
 ↓
Internet Gateway
 ↓
Public IPv4
 ↓
Security Group
```

A subnet being labelled “Public” is not enough — the network path must actually provide internet connectivity.

### Recommended Troubleshooting Order

```text
EC2
 ↓
Apache
 ↓
User Data
 ↓
Metadata
 ↓
Security Group
 ↓
Subnet / Route Table
 ↓
Target Group
 ↓
ALB
 ↓
Browser
```

This approach makes it easier to isolate the problem instead of changing multiple AWS settings at once.

---

## Old Instance Using the Previous Configuration

During troubleshooting, one older instance was still running the broken version of the User Data script while a newer replacement was using the corrected version.

**What happened:**
- The EC2 launch times showed the difference
- The old instance was terminated
- The Auto Scaling Group detected that capacity had dropped below the desired value
- It automatically launched a replacement using the corrected configuration

**Lesson:** When troubleshooting an ASG, always check:

- Instance launch time
- Launch Template version
- User Data
- Availability Zone
- Target health
- ASG Activity history

Changing a Launch Template does **not** automatically reconfigure existing instances.

---

# Auto Scaling Test (Optional but Recommended)

To demonstrate actual scale-out, you can add a target-tracking scaling policy.

1. Open **EC2 → Auto Scaling Groups → CloudHER-ASG → Automatic scaling**
2. Create a target tracking policy:
   - Metric: **Average CPU Utilization**
   - Target value: **50%**
3. On one of the running instances, generate CPU load:

```bash
sudo dnf install stress-ng -y
stress-ng --cpu 2 --timeout 300s
```

4. Monitor:
   - **CloudWatch → EC2 Metrics**
   - **EC2 → Auto Scaling Groups → CloudHER-ASG → Activity**

**Expected behaviour:**

```text
CPU increases
      ↓
CloudWatch detects increased utilization
      ↓
Scaling policy is triggered
      ↓
ASG launches another EC2 instance
      ↓
New instance joins Target Group
      ↓
Health check passes
      ↓
ALB can send traffic to it
```

This demonstrates **horizontal scaling** rather than manually creating servers.

---

# Key Concepts Learned

### Auto Scaling vs Load Balancing

They solve different problems:

```text
ALB:
"Which healthy instance should receive this request?"

ASG:
"How many instances should be running?"
```

Together they create a scalable application.

### Multi-AZ Availability

Running instances in:

```text
us-east-1a
us-east-1b
```

reduces dependence on a single Availability Zone.

### Health Checks

An EC2 instance can be:

```text
Running
```

but still:

```text
Unhealthy
```

from the ALB’s perspective.  
This is why Target Group health checks are important.

### Configuration Consistency

```text
Launch Template
       ↓
User Data
       ↓
Consistent EC2 instances
       ↓
Healthy Target Group
       ↓
Reliable ALB traffic
```

---

# Skills Practiced

- Amazon EC2
- Amazon VPC
- Security Groups
- Application Load Balancer
- Target Groups
- Auto Scaling Groups
- Launch Templates
- CloudWatch
- Multi-AZ architecture
- Amazon Linux
- Apache
- Bash / User Data
- EC2 Instance Metadata Service (IMDSv2)
- Health checks
- Horizontal scaling
- Cloud troubleshooting

---

# Cleanup

AWS resources can incur charges if they remain active.  
After completing the lab, clean up in this order:

1. Scale the Auto Scaling Group desired capacity to **0**, or delete the Auto Scaling Group
2. Terminate any remaining EC2 instances
3. Delete the Application Load Balancer
4. Delete the Target Group
5. Delete unused Launch Templates
6. Remove unused CloudWatch alarms and other resources created for the lab
7. Verify the **AWS Billing** dashboard

---

# What I Learned

The biggest lesson from this project was that AWS services are not isolated.  
A working application depends on several layers working together:

```text
Networking
    ↓
Security
    ↓
EC2
    ↓
Application
    ↓
Target Group
    ↓
Load Balancer
    ↓
Auto Scaling
    ↓
Monitoring
```

The troubleshooting experience was especially valuable. Problems with **public connectivity, IMDSv2, User Data, Launch Template versions, and Auto Scaling behaviour** showed why cloud troubleshooting should be systematic rather than based on guesswork.

This lab moved my understanding from simply **“running an EC2 instance”** to thinking about **availability, scalability, automation, health, and failure recovery**.

---

# Author

**Daniel Nzioki Musyoka**

Data & AI | Cloud Computing | Data Engineering | DevOps

- GitHub: [Daniel059](https://github.com/Daniel059)
- Portfolio: [Daniel Nzioki Musyoka — Data & AI Portfolio](https://daniel-nzioki-musyoka-data-and-ai-pro.netlify.app/)

## Acknowledgements

This project was completed as part of the **CloudHER by WIICA** Cloud Computing mentorship program.

Special appreciation to my mentor **Rajpreet Gill** for the guidance and technical direction throughout the program.

---

## License

This project is intended for educational and portfolio purposes.
```
