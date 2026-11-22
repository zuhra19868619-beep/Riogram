from test_messaging import context

def test_sms_unconfigured_fails_closed(context,monkeypatch):
    client,ids,headers=context
    for key in ("TWILIO_ACCOUNT_SID","TWILIO_AUTH_TOKEN","TWILIO_VERIFY_SERVICE_SID"):
        monkeypatch.delenv(key,raising=False)
    response=client.post("/api/v1/auth/request-code",json={"phone_number":"+12025550123"})
    assert response.status_code==503
    response=client.post("/api/v1/auth/verify-code",json={"phone_number":"+12025550123","code":"123456"})
    assert response.status_code==503

def test_sms_phone_validation(context):
    client,ids,headers=context
    response=client.post("/api/v1/auth/request-code",json={"phone_number":"12345"})
    assert response.status_code==422
