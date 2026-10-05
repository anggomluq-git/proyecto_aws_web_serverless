import json
import boto3

# Conexion con DynamoDB y referencia a la tabla del contador.
dynamodb = boto3.resource("dynamodb", region_name="eu-north-1")
table = dynamodb.Table('Cuenta_Visitas_tf')

# event: informacion de la peticion. context: informacion del entorno de ejecucion.
def lambda_handler(event, context):
    # Suma 1 al contador y devuelve el nuevo valor.
    response = table.update_item(
        Key={'id': 'cuenta_visitas'},
        UpdateExpression='ADD num_visitas :inc',
        ExpressionAttributeValues={':inc': 1},
        ReturnValues='UPDATED_NEW'
    )

    new_count = int(response['Attributes']['num_visitas'])

    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*"
        },
        # json.dumps convierte el diccionario en un string JSON.
        # Es lo que comprueban los tests: que devuelva el valor real de DynamoDB.
        "body": json.dumps({"num_visitas": new_count})
    }