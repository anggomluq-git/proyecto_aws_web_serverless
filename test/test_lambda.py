import sys
from pathlib import Path

# Anade la carpeta "lmbda" al path para poder importar lambda_function.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lmbda"))

import json
from unittest.mock import patch
import lambda_function


# Sustituye la tabla real de DynamoDB por un mock: el test no toca AWS.
@patch("lambda_function.table")
def test_lambda_handler(mock_table):
    # DynamoDB simulado: devuelve que el contador vale 10.
    mock_table.update_item.return_value = {
        "Attributes": {
            "num_visitas": 10
        }
    }

    response = lambda_function.lambda_handler({}, {})

    # Comprueba que la respuesta es correcta y que el numero es el que
    # devolvio DynamoDB (no uno inventado por la Lambda).
    assert response["statusCode"] == 200

    body = json.loads(response["body"])

    assert body == {
        "num_visitas": 10
    }

    # Comprueba que la Lambda llamo a DynamoDB con los parametros esperados.
    mock_table.update_item.assert_called_once_with(
        Key={"id": "cuenta_visitas"},
        UpdateExpression="ADD num_visitas :inc",
        ExpressionAttributeValues={":inc": 1},
        ReturnValues="UPDATED_NEW",
    )