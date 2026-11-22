from test_messaging import context
def test_group_lifecycle(context):
    client,ids,headers=context
    response=client.post("/api/v1/groups",json={"title":"Friends","member_ids":[ids[1]]},headers=headers(0))
    assert response.status_code==201,response.text
    gid=response.json()["id"]
    assert len(client.get(f"/api/v1/groups/{gid}/members",headers=headers(1)).json())==2
    assert client.get(f"/api/v1/groups/{gid}/members",headers=headers(2)).status_code==404
    assert client.patch(f"/api/v1/groups/{gid}",json={"title":"New"},headers=headers(1)).status_code==403
    assert client.patch(f"/api/v1/groups/{gid}",json={"title":"New"},headers=headers(0)).json()["title"]=="New"
    assert client.post(f"/api/v1/groups/{gid}/members",json={"user_id":ids[2]},headers=headers(0)).status_code==201
    assert client.post(f"/api/v1/chats/{gid}/messages",json={"client_message_id":"g1","text":"Hello"},headers=headers(2)).status_code==201
    assert client.delete(f"/api/v1/groups/{gid}/members/{ids[0]}",headers=headers(0)).status_code==409
    assert client.delete(f"/api/v1/groups/{gid}/members/{ids[2]}",headers=headers(0)).status_code==204
    assert client.get(f"/api/v1/chats/{gid}/messages",headers=headers(2)).status_code==404
