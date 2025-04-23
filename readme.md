# AWS Hands-on Workshop: Infrastructure as Code and Advanced Monitoring

## Setup Requirements
- AWS Console access to the sandbox account
- Default VPC available
- IAM permissions to create resources

## Workshop Modules

### Module 1: Infrastructure as Code with CloudFormation (45 minutes)

#### 1.1 CloudFormation Template Review
1. Review the provided CloudFormation template
2. Understand how each resource from the previous workshop is defined as code
3. Note the benefits of infrastructure as code (repeatability, version control, consistency)

#### 1.2 Template Preparation
1. Download the CloudFormation template
2. Identify the parameters you'll need:
   - Your initials for resource naming
   - Database username and password
   - VPC ID of the default VPC
   - Subnet IDs for two public subnets in the default VPC

#### 1.3 Stack Deployment
1. Navigate to CloudFormation in the AWS Console
2. Click "Create stack" > "With new resources (standard)
3. Upload the template file "cloudformation.yaml"
4. Fill in the required parameters:
   - InitialsParam: Your initials (e.g., `jama` for Jan Marek)
   - DBUsername: Database username
   - DBPassword: Database password (use `Workshop#123` for this lab)
   - VpcId: Select your default VPC
   - Subnet1 and Subnet2: Select two different subnets
5. Review and create the stack
6. Monitor the stack creation events
7. Once complete, go to the Outputs tab and note:
   - DatabaseEndpoint
   - LoadBalancerEndpoint
   - ApiGatewayEndpoint

#### 1.4 Testing the Deployed Application
1. Access the API Gateway endpoint in a browser
2. Verify the Nginx welcome page loads
3. Navigate to the ECS console and check that your service is running with 1 task
4. Navigate to the RDS console and verify the database instance is available

### Module 2: Creating EC2 Access to RDS (30 minutes)

#### 2.1 EC2 Security Group Creation
1. Navigate to EC2 → Security Groups
2. Create a new security group:
   - Name: `{initials}-ec2-sg`
   - Description: "Security group for EC2 RDS client"
   - VPC: Default VPC
   - Inbound rules: Allow SSH (22) from your IP
3. Add a rule to the DB security group:
   - Select the `{initials}-db-sg` security group
   - Add inbound rule: PostgreSQL (5432) from the new EC2 security group

#### 2.2 EC2 Instance Setup
1. Navigate to EC2 → Instances
2. Click "Launch instances"
3. Name: "{initials}-ec2"
4. Choose Amazon Linux 2023 AMI
5. Select t2.micro instance type
6. Create a new key pair
6. Configure instance details:
   - Network: Default VPC
   - Subnet: No preference
   - Auto-assign Public IP: Enable
7. Configure Security Group: Select the security group created earlier
8. Add storage: Leave as default (8 GB)
10. Launch instance
12. Wait for the instance to be in the "running" state

#### 2.3 Connect and Configure the EC2 Instance
1. Connect to your EC2 instance via SSH:
   ```
   ssh -i your-key.pem ec2-user@your-ec2-public-dns
   ```
2. Install PostgreSQL client:
   ```
   sudo yum update -y
   sudo yum install -y postgresql15
   ```
3. Create a script to connect to the database:
   ```
   echo '#!/bin/bash
   PGPASSWORD=Workshop#123 psql -h YOUR_RDS_ENDPOINT -U YOUR_DB_USERNAME -d YOUR_DB_NAME
   ' > connect-rds.sh
   ```
4. Replace placeholders with your actual values from stack outputs
5. Make the script executable:
   ```
   chmod +x connect-rds.sh
   ```
6. Test the connection:
   ```
   ./connect-rds.sh
   ```
7. In the PostgreSQL prompt, create a test table:
   ```
   CREATE TABLE test_table (
     id SERIAL PRIMARY KEY,
     message TEXT,
     created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
   );
   
   INSERT INTO test_table (message) VALUES ('Hello from EC2 client!');
   
   SELECT * FROM test_table;
   ```
8. Type `\q` to exit PostgreSQL

### Module 3: RDS Monitoring and Alerting (30 minutes)

#### 3.1 CloudWatch Alarm Creation
1. Navigate to CloudWatch → Alarms → All alarms → Create alarm
2. Select "Select metric"
3. Navigate to RDS → DBInstanceIdentifier
4. Find your database instance and select CPUUtilization
5. Configure the metric:
   - Statistic: Average
   - Period: 1 minute
6. Configure the alarm:
   - Threshold type: Static
   - Define the alarm condition: Greater than 80%
   - Additional configuration: 
     - Datapoints to alarm: 1 out of 1
     - Missing data treatment: Treat missing data as missing
7. Configure actions:
   - Create a new SNS topic: `{initials}-rds-alarm`
   - Add your email as a notification endpoint
   - Click "Create topic"
8. Add alarm name and description:
   - Name: `{initials}-rds-cpu-alarm`
   - Description: "Alarm when RDS CPU exceeds 80%"
9. Preview the configuration and click "Create alarm"
10. Confirm the subscription in your email
   
#### 3.2 Create a Second Alarm for Database Connections
1. Follow the same steps to create another alarm for DatabaseConnections
2. Set the threshold to 10 connections (for testing purposes)
3. Use the same SNS topic for notifications
4. Name it `{initials}-rds-connections-alarm`

### Module 4: Load Testing with EC2 Shell Script (45 minutes)

#### 4.1 Install Required Packages on EC2
1. Connect to your EC2 instance:
   ```
   ssh -i your-key.pem ec2-user@your-ec2-public-dns
   ```
2. Install required packages:
   ```
   sudo yum update -y
   sudo yum install -y postgresql15 jq bc
   ```

#### 4.2 Create the Load Testing Script
1. Create a new script file:
   ```
   nano rds-load-test.sh
   ```
2. Copy and paste the following script:
   ```bash
   #!/bin/bash
   
   # RDS Load Test Script
   # Usage: ./rds-load-test.sh [concurrent_processes] [duration_seconds]
   
   # Configuration
   DB_HOST="YOUR_RDS_ENDPOINT"  # Replace with your RDS endpoint
   DB_NAME="YOUR_DB_NAME"       # Replace with your database name
   DB_USER="YOUR_DB_USERNAME"   # Replace with your database username
   DB_PASSWORD="Workshop#123"   # Replace with your database password
   
   # Default parameters
   CONCURRENT=${1:-10}          # Default: 10 concurrent processes
   DURATION=${2:-30}            # Default: 30 seconds runtime
   
   # Colors for output
   GREEN='\033[0;32m'
   YELLOW='\033[1;33m'
   BLUE='\033[0;34m'
   RED='\033[0;31m'
   NC='\033[0m' # No Color
   
   # Ensure the test table exists
   echo -e "${BLUE}Creating test table if it doesn't exist...${NC}"
   PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME <<EOF
   CREATE TABLE IF NOT EXISTS load_test (
       id SERIAL PRIMARY KEY,
       random_data TEXT,
       created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
   );
   EOF
   
   if [ $? -ne 0 ]; then
       echo -e "${RED}Failed to create test table. Check your connection parameters.${NC}"
       exit 1
   fi
   
   # Generate a random string of specified length
   generate_random_string() {
       local length=$1
       cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w $length | head -n 1
   }
   
   # Function to run queries in a loop
   run_queries() {
       local process_id=$1
       local end_time=$2
       local query_count=0
       
       while [ $(date +%s) -lt $end_time ]; do
           # Generate random data for insert
           RANDOM_DATA=$(generate_random_string 100)
           
           # Insert data (generates load)
           PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "INSERT INTO load_test (random_data) VALUES ('$RANDOM_DATA');" >/dev/null 2>&1
           
           # Run a complex query (generates CPU load)
           PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "
           SELECT count(*),
               min(created_at),
               max(created_at),
               avg(length(random_data))
           FROM load_test
           GROUP BY date_trunc('second', created_at)
           ORDER BY 1 DESC
           LIMIT 10;" >/dev/null 2>&1
           
           query_count=$((query_count + 2))
           
           # Optional small delay to prevent overwhelming the system
           sleep 0.05
       done
       
       # Return the query count
       echo $query_count
   }
   
   # Main execution
   echo -e "${YELLOW}Starting load test with ${CONCURRENT} parallel processes for ${DURATION} seconds${NC}"
   
   # Calculate end time
   START_TIME=$(date +%s)
   END_TIME=$((START_TIME + DURATION))
   
   # Launch background processes
   pids=()
   for i in $(seq 1 $CONCURRENT); do
       run_queries $i $END_TIME > /tmp/queries_$i.log &
       pids+=($!)
       echo -e "${BLUE}Started process $i with PID ${pids[-1]}${NC}"
   done
   
   # Wait for all processes to complete
   echo -e "${YELLOW}Waiting for all processes to complete...${NC}"
   for pid in ${pids[@]}; do
       wait $pid
   done
   
   # Collect and sum up results
   TOTAL_QUERIES=0
   for i in $(seq 1 $CONCURRENT); do
       PROCESS_QUERIES=$(cat /tmp/queries_$i.log)
       TOTAL_QUERIES=$((TOTAL_QUERIES + PROCESS_QUERIES))
       rm /tmp/queries_$i.log
   done
   
   # Calculate elapsed time and queries per second
   ELAPSED_SECONDS=$(($(date +%s) - START_TIME))
   QUERIES_PER_SECOND=$(echo "scale=2; $TOTAL_QUERIES / $ELAPSED_SECONDS" | bc)
   
   # Print results
   echo -e "${GREEN}Load test completed${NC}"
   echo -e "${GREEN}Total queries: ${TOTAL_QUERIES}${NC}"
   echo -e "${GREEN}Duration: ${ELAPSED_SECONDS} seconds${NC}"
   echo -e "${GREEN}Rate: ${QUERIES_PER_SECOND} queries/second${NC}"
   
   # Show the data count in the table
   echo -e "${BLUE}Current row count in load_test table:${NC}"
   PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT COUNT(*) FROM load_test;"
   ```
3. Replace placeholder values with your actual values:
   ```
   DB_HOST="your-db-endpoint.rds.amazonaws.com"  # From CloudFormation outputs
   DB_NAME="your_db_name"                        # Usually postgres or the name you specified
   DB_USER="your_username"                       # From CloudFormation parameters
   DB_PASSWORD="Workshop#123"                    # From CloudFormation parameters
   ```
4. Make the script executable:
   ```
   chmod +x rds-load-test.sh
   ```

#### 4.3 Running Load Tests
1. Run a test with moderate load:
   ```
   ./rds-load-test.sh 10 30
   ```
   This will run 10 concurrent processes for 30 seconds.

2. Monitor the output to see the query execution rate and results.

#### 4.4 Testing with Higher Load
1. Run the script with higher concurrency to generate more load:
   ```
   ./rds-load-test.sh 20 60
   ```
   This will run 20 concurrent processes for 60 seconds.

2. In the AWS Console, monitor:
   - CloudWatch metrics for your RDS instance
   - CloudWatch alarm status
   - Email notifications from your alarms

### Module 5: Auto-Remediation (30 minutes)

#### 5.1 Creating an SNS Topic for Automatic Actions
1. Navigate to SNS → Topics
2. Create a new topic:
   - Type: Standard
   - Name: `{initials}-remediation-topic`
   - Display name: "RDS Remediation"
3. Click "Create topic"
4. Create a subscription:
   - Protocol: Email
   - Endpoint: Your email address
5. Click "Create subscription" and confirm in your email

#### 5.2 Creating a Simple Lambda Function for Auto-Remediation
1. Navigate to Lambda → Functions
2. Click "Create function"
3. Select "Author from scratch"
4. Configure basic information:
   - Function name: `{initials}-rds-remediation`
   - Runtime: Python 3.13
   - Execution role: Create a new role with basic Lambda permissions
5. Click "Create function"
6. Replace the default code with this simple Python script:

```python
import json

def lambda_handler(event, context):
    print("Auto-remediation function activated!")
    
    # Parse the SNS message
    message = json.loads(event['Records'][0]['Sns']['Message'])
    
    # Extract alarm details
    alarm_name = message['AlarmName']
    alarm_description = message.get('AlarmDescription', 'No description')
    trigger_time = message['StateChangeTime']
    
    # Get the RDS instance identifier from the alarm dimensions
    dimensions = message['Trigger']['Dimensions']
    instance_id = next((dim['value'] for dim in dimensions if dim['name'] == 'DBInstanceIdentifier'), 'Unknown')
    
    print(f"Alarm: {alarm_name}")
    print(f"Description: {alarm_description}")
    print(f"RDS Instance: {instance_id}")
    print(f"Triggered at: {trigger_time}")
    print(f"Alarm state: {message['NewStateValue']}")
    
    # In a real scenario, you would implement actual remediation here
    print("Possible remediation actions would include:")
    print("1. Scaling up the instance")
    print("2. Creating a read replica")
    print("3. Killing long-running queries")
    print("4. Enabling Performance Insights")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Remediation function activated',
            'alarm': alarm_name,
            'instance': instance_id
        })
    }
```

7. Click "Deploy" to save the changes

#### 5.3 Add Lambda Permission for SNS
1. In the Lambda function, go to the Configuration tab
2. Click on "Permissions" and note the role name
3. Navigate to the "Triggers" section
4. Click "Add trigger"
5. Configure trigger:
   - Select trigger: SNS
   - SNS topic: Select the `{initials}-remediation-topic` created earlier
6. Click "Add"

#### 5.4 Update CloudWatch Alarm for Auto-Remediation
1. Navigate to CloudWatch → Alarms
2. Select your RDS CPU alarm
3. Click "Actions" → "Edit"
4. Under the "Notification" section:
   - Make sure your original email notification is still set up
   - Add another action: Select the `{initials}-remediation-topic` SNS topic
5. Click "Update"

#### 5.5 Testing Auto-Remediation
1. Run the EC2 load test script with higher concurrency:
   ```
   ./rds-load-test.sh 30 120
   ```
2. Monitor in real-time:
   - CloudWatch alarm status
   - Lambda execution logs in CloudWatch Logs
   - SNS notifications in your email
   - Navigate to Lambda → Functions → `{initials}-rds-remediation` → Monitor tab to see invocation data
3. After the test completes, check the lambda logs:
   - In the Lambda console, select your function
   - Go to the "Monitor" tab and click "View CloudWatch logs"
   - Find the most recent log stream and verify that your function was triggered

### Module 6: Cleanup (15 minutes)
1. Delete Lambda functions
2. Delete CloudWatch alarms
3. Delete SNS topics
4. Terminate the EC2 instance
5. Delete the CloudFormation stack (this will remove all resources created by the template)
6. Remove any remaining security groups that were manually created

## Additional Resources
- [AWS Documentation: CloudFormation](https://docs.aws.amazon.com/cloudformation/)
- [AWS Documentation: Lambda](https://docs.aws.amazon.com/lambda/)
- [AWS Documentation: CloudWatch](https://docs.aws.amazon.com/cloudwatch/)
- [AWS Documentation: EC2](https://docs.aws.amazon.com/ec2/)
- [AWS Well-Architected Framework: Reliability Pillar](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/welcome.html)