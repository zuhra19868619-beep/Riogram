from test_messaging import context

def test_contacts(context):
    client,ids,headers=context
    response=client.post("/api/v1/contacts/match",json={"phones":["+12025550101","+12025550102","+12025550100"]},headers=headers(0))
    assert response.status_code==200
    assert {u["id"] for u in response.json()["contacts"]}=={ids[1],ids[2]}
    assert client.post("/api/v1/contacts/match",json={"phones":["555-0101"]},headers=headers(0)).status_code==422
    assert client.post("/api/v1/contacts/match",json={"phones":["+12025550101"]}).status_code==401

def test_device(context):
    client,ids,headers=context
    body={"token":"a"*32,"platform":"android"}
    assert client.post("/api/v1/devices",json=body,headers=headers(0)).status_code==201
    assert client.post("/api/v1/devices",json=body,headers=headers(0)).status_code==201
    assert client.request("DELETE","/api/v1/devices",json=body,headers=headers(0)).status_code==204
    assert client.post("/api/v1/devices",json={"token":"x","platform":"android"},headers=headers(0)).status_code==422

def test_ws_reject_invalid(context):
    client,ids,headers=context
    from starlette.websockets import WebSocketDisconnect
    with client.websocket_connect("/api/v1/ws") as ws:
        ws.send_json({"token":"bad"})
        try:
            ws.receive_json()
            assert False,"Invalid token accepted"
        except WebSocketDisconnect as exc:
            assert exc.code==1008
