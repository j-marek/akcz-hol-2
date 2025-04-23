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