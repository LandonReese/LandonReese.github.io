import boto3
import json

# Connect to DB
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('visitor-count')

def lambda_handler(event, context):
    try:
        # Atomic update: Increment 'visits' by 1
        response = table.update_item(
            Key={'id': 'count'},
            UpdateExpression="ADD visits :inc",
            ExpressionAttributeValues={':inc': 1},
            ReturnValues="UPDATED_NEW"
        )
        
        # Convert Decimal to int for JSON serialization
        count = int(response['Attributes']['visits'])
        
        return {
            'statusCode': 200,
            'body': json.dumps({'count': count})
        }
    except Exception as e:
        print(e)
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Could not connect to database'})
        }