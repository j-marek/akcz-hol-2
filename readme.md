# AWS Hands-on Workshop: Infrastructure as Code and Advanced Monitoring

## Overview
This follow-up workshop builds on the previous application stack experience by implementing infrastructure as code (IaC) with CloudFormation and adding advanced monitoring and testing capabilities. You'll deploy the existing architecture through CloudFormation, then extend it with EC2 connectivity, monitoring, and stress testing features.

**Target Audience:** IT Operations professionals with basic AWS experience  
**Prerequisites:** Completion of the previous "Application Stack" workshop

## Architecture
By the end of this workshop, you will have created the following architecture:

```
Internet → API Gateway → Application Load Balancer → ECS (Containers) → RDS PostgreSQL
                                                   ↑
                                                   EC2 (for DB access)
                                                   ↓
CloudWatch Alarms ← RDS Metrics ← Lambda (Load Testing) 
       ↓
Auto-remediation
```

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
2. Click "Create stack" with new resources
3. Upload the template file
4. Fill in the required parameters:
   - InitialsParam: Your initials (e.g., `jama` for Jan Marek)
   - DBUsername: Database username
   - DBPassword: Database password (use `Workshop#123` for this lab)
   - VpcId: Select your default VPC
   - Subnet1 and Subnet2: Select two different public subnets
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
3. Choose Amazon Linux 2023 AMI
4. Select t3.micro instance type
5. Configure instance details:
   - Network: Default VPC
   - Subnet: Select any public subnet
   - Auto-assign Public IP: Enable
6. Add storage: Leave as default (8 GB)
7. Add tags: Name = `{initials}-rds-client`
8. Configure Security Group: Select the security group created earlier
9. Review and launch
10. Create or select an existing key pair and download it
11. Launch the instance
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
1. Navigate to CloudWatch → Alarms → Create alarm
2. Select "Select metric"
3. Navigate to RDS → Per-Database Metrics
4. Find your database instance and select CPUUtilization
5. Configure the metric:
   - Statistic: Average
   - Period: 1 minute
6. Configure the alarm:
   - Threshold type: Static
   - Define the alarm condition: Greater than 80%
   - Additional configuration: 
     - Datapoints to alarm: 3 out of 3
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

### Module 4: Load Testing with Lambda (45 minutes)

#### 4.1 Lambda Security Group Setup
1. Navigate to EC2 → Security Groups
2. Create a new security group:
   - Name: `{initials}-lambda-sg`
   - Description: "Security group for RDS load generator Lambda"
   - VPC: Default VPC
   - No inbound rules needed
3. Add a rule to the DB security group:
   - Select the `{initials}-db-sg` security group
   - Add inbound rule: PostgreSQL (5432) from the Lambda security group

#### 4.2 Lambda Execution Role Creation
1. Navigate to IAM → Roles
2. Click "Create role"
3. Select AWS service as the trusted entity
4. Choose Lambda as the use case
5. Click "Next: Permissions"
6. Attach the following policies:
   - AWSLambdaVPCAccessExecutionRole
   - AmazonRDSDataFullAccess
7. Click "Next: Tags"
8. Add tag: Name = `{initials}-lambda-role`
9. Review and create the role

#### 4.3 Lambda Function Creation
1. Navigate to Lambda → Functions
2. Click "Create function"
3. Choose "Author from scratch"
4. Configure basic information:
   - Function name: `{initials}-rds-load-generator`
   - Runtime: Node.js 16.x
   - Execution role: Use the role created earlier
5. Click "Create function"
6. Under VPC configuration:
   - VPC: Select default VPC
   - Subnets: Select at least two subnets
   - Security group: Select the Lambda security group
7. Set environment variables:
   - DB_HOST: Your RDS endpoint
   - DB_NAME: Your database name
   - DB_USER: Your database username
   - DB_PASSWORD: Workshop#123
8. Paste the following code:

```javascript
const { Client } = require('pg');

exports.handler = async (event, context) => {
  const concurrency = event.concurrency || 10; // Number of parallel queries
  const duration = event.duration || 30; // Duration in seconds
  
  console.log(`Starting load test with ${concurrency} parallel connections for ${duration} seconds`);
  
  const client = new Client({
    host: process.env.DB_HOST,
    database: process.env.DB_NAME,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    port: 5432,
  });
  
  try {
    await client.connect();
    
    // Create test table if it doesn't exist
    await client.query(`
      CREATE TABLE IF NOT EXISTS load_test (
        id SERIAL PRIMARY KEY,
        random_data TEXT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    `);
    
    // Start time
    const startTime = Date.now();
    const endTime = startTime + (duration * 1000);
    
    let totalQueries = 0;
    
    // Run load test
    const tasks = [];
    for (let i = 0; i < concurrency; i++) {
      tasks.push(runLoadQueries(client, endTime));
    }
    
    const results = await Promise.all(tasks);
    totalQueries = results.reduce((sum, count) => sum + count, 0);
    
    const elapsedSeconds = (Date.now() - startTime) / 1000;
    console.log(`Load test completed: ${totalQueries} queries executed in ${elapsedSeconds.toFixed(2)} seconds`);
    console.log(`Rate: ${(totalQueries / elapsedSeconds).toFixed(2)} queries/second`);
    
    return {
      statusCode: 200,
      body: JSON.stringify({
        totalQueries,
        queriesPerSecond: totalQueries / elapsedSeconds,
        durationSeconds: elapsedSeconds
      })
    };
  } catch (error) {
    console.error('Error during load test:', error);
    return {
      statusCode: 500,
      body: JSON.stringify({ error: error.message })
    };
  } finally {
    await client.end();
  }
};

async function runLoadQueries(client, endTime) {
  let queryCount = 0;
  
  while (Date.now() < endTime) {
    try {
      // Insert random data (generates load)
      await client.query(`
        INSERT INTO load_test (random_data)
        VALUES ($1)
      `, [generateRandomString(100)]);
      
      // Run a complex query (generates CPU load)
      await client.query(`
        SELECT count(*), 
               min(created_at), 
               max(created_at), 
               avg(length(random_data))
        FROM load_test
        GROUP BY date_trunc('second', created_at)
        ORDER BY 1 DESC
        LIMIT 10
      `);
      
      queryCount += 2;
    } catch (error) {
      console.error('Query error:', error);
      // Continue despite errors
    }
  }
  
  return queryCount;
}

function generateRandomString(length) {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let result = '';
  for (let i = 0; i < length; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}
```

9. Set a longer timeout (2-3 minutes) in the Configuration tab
10. Click "Deploy" to save the changes

#### 4.4 Testing the Load Generator
1. Create a test event with the following JSON:
   ```json
   {
     "concurrency": 20,
     "duration": 60
   }
   ```
2. Save the test event and click "Test"
3. Monitor the function execution in the console
4. Switch to another tab to view:
   - CloudWatch metrics for your RDS instance
   - CloudWatch alarm status
   - Your email for alarm notifications

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

#### 5.2 Creating a Lambda Function for Auto-Remediation
1. Create a new Lambda function:
   - Name: `{initials}-rds-remediation`
   - Runtime: Node.js 16.x
   - Create a new execution role with basic Lambda permissions
2. Add the AmazonRDSFullAccess managed policy to the role
3. Add the following code:

```javascript
const AWS = require('aws-sdk');
const rds = new AWS.RDS();

exports.handler = async (event, context) => {
  console.log('Received event:', JSON.stringify(event, null, 2));
  
  // Parse the SNS message
  const message = JSON.parse(event.Records[0].Sns.Message);
  console.log('Alarm message:', JSON.stringify(message, null, 2));
  
  // Get the RDS instance identifier from the alarm
  const alarmName = message.AlarmName;
  const instanceId = message.Trigger.Dimensions.find(d => d.name === 'DBInstanceIdentifier').value;
  
  console.log(`Alarm ${alarmName} triggered for RDS instance ${instanceId}`);
  
  if (message.NewStateValue === 'ALARM') {
    console.log('Taking remediation action...');
    
    // You can implement different remediation actions based on the alarm
    // Example: Get instance info
    const instanceInfo = await rds.describeDBInstances({
      DBInstanceIdentifier: instanceId
    }).promise();
    
    console.log('Instance info:', JSON.stringify(instanceInfo, null, 2));
    
    // Example action: Log current connections
    console.log('Getting current connection info...');
    
    // You could implement other actions like:
    // - Increase instance class (would require a reboot)
    // - Create a read replica
    // - Run EXPLAIN ANALYZE on slow queries
    
    return {
      statusCode: 200,
      body: JSON.stringify({
        message: 'Remediation action initiated',
        instanceId: instanceId
      })
    };
  } else {
    console.log('Alarm is not in ALARM state. No action taken.');
    return {
      statusCode: 200,
      body: JSON.stringify({
        message: 'No action needed',
        instanceId: instanceId
      })
    };
  }
};
```

4. Click "Deploy" to save the changes

#### 5.3 Add Lambda Permission for SNS
1. In the Lambda function, go to the Configuration tab
2. Click on "Triggers" → "Add trigger"
3. Select "SNS" as the source
4. Select your remediation topic
5. Click "Add"

#### 5.4 Update CloudWatch Alarm for Auto-Remediation
1. Navigate back to CloudWatch → Alarms
2. Select your RDS CPU alarm
3. Click "Actions" → "Edit"
4. Under the "Actions" section, add your remediation SNS topic
5. Save changes

#### 5.5 Testing Auto-Remediation
1. Run the load generator Lambda again with a higher concurrency value:
   ```json
   {
     "concurrency": 30,
     "duration": 120
   }
   ```
2. Monitor in real-time:
   - CloudWatch alarm status
   - Lambda execution logs for both functions
   - SNS notifications in your email
   - RDS console for any changes

### Module 6: Cleanup (15 minutes)
1. Delete the Lambda functions
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