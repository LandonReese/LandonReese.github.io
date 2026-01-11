import boto3
import json
import time
import os

dynamodb = boto3.resource('dynamodb')
visitor_table = dynamodb.Table('visitor-count')
rate_limit_table = dynamodb.Table('visitor-counter-rate-limit')

MAX_REQUESTS_PER_MINUTE = 10
RATE_LIMIT_WINDOW = 60

def get_client_ip(event):
    request_context = event.get('requestContext', {})
    if 'http' in request_context:
        return request_context['http'].get('sourceIp')
    if 'identity' in request_context:
        return request_context['identity'].get('sourceIp')
    headers = event.get('headers', {})
    return headers.get('x-forwarded-for', '').split(',')[0].strip() or 'unknown'

def check_rate_limit(ip_address):
    try:
        current_time = int(time.time())
        window_start = current_time - RATE_LIMIT_WINDOW
        
        response = rate_limit_table.get_item(Key={'ip_address': ip_address})
        
        if 'Item' in response:
            item = response['Item']
            recent_requests = [t for t in item.get('request_times', []) if t > window_start]
            
            if len(recent_requests) >= MAX_REQUESTS_PER_MINUTE:
                return False, len(recent_requests)
            
            recent_requests.append(current_time)
        else:
            recent_requests = [current_time]
        
        rate_limit_table.put_item(
            Item={
                'ip_address': ip_address,
                'request_times': recent_requests,
                'ttl': current_time + 3600
            }
        )
        return True, len(recent_requests)
        
    except Exception as e:
        print(f"Rate limit check error: {e}")
        return False, 0 

def lambda_handler(event, context):
    if event.get('requestContext', {}).get('http', {}).get('method') != 'GET':
        return {'statusCode': 405, 'body': json.dumps({'error': 'Method not allowed'})}
    
    client_ip = get_client_ip(event)
    allowed, count = check_rate_limit(client_ip)
    
    if not allowed:
        return {
            'statusCode': 429,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({'error': 'Too many requests. Slow down.'})
        }
    
    try:
        response = visitor_table.update_item(
            Key={'id': 'count'},
            UpdateExpression="ADD visits :inc",
            ExpressionAttributeValues={':inc': 1},
            ReturnValues="UPDATED_NEW"
        )
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json'
            },
            'body': json.dumps({'count': int(response['Attributes']['visits'])})
        }
    except Exception as e:
        print(f"Error: {e}")
        return {'statusCode': 500, 'body': json.dumps({'error': 'Internal Server Error'})}