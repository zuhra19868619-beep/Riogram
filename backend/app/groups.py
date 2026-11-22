import uuid
from fastapi import APIRouter,HTTPException
from pydantic import BaseModel,Field
from sqlalchemy import select
from .messaging import DB,UserDep,require_member
from .models import Chat,ChatMember,User
router=APIRouter(prefix="/api/v1",tags=["groups"])
class GroupCreate(BaseModel):
    title:str=Field(min_length=1,max_length=160)
    member_ids:list[uuid.UUID]=Field(min_length=1,max_length=199)
class GroupMember(BaseModel):
    user_id:uuid.UUID
class GroupRename(BaseModel):
    title:str=Field(min_length=1,max_length=160)
def admin_only(db,chat_id,user_id):
    member=db.scalar(select(ChatMember).where(ChatMember.chat_id==chat_id,ChatMember.user_id==user_id))
    chat=db.get(Chat,chat_id)
    if not chat or chat.type!="group" or not member or member.role!="admin":
        raise HTTPException(403,"Group administrator required")
    return chat
@router.post("/groups",status_code=201)
def create_group(data:GroupCreate,db:DB,user:UserDep):
    ids=set(map(str,data.member_ids));ids.discard(user.id)
    if not ids:raise HTTPException(422,"At least one other member is required")
    if set(db.scalars(select(User.id).where(User.id.in_(ids))).all())!=ids:
        raise HTTPException(404,"Some users do not exist")
    title=data.title.strip()
    if not title:raise HTTPException(422,"Title cannot be blank")
    chat=Chat(type="group",title=title);db.add(chat);db.flush()
    db.add(ChatMember(chat_id=chat.id,user_id=user.id,role="admin"))
    for uid in ids:db.add(ChatMember(chat_id=chat.id,user_id=uid,role="member"))
    db.commit()
    return {"id":chat.id,"title":chat.title,"type":chat.type}
@router.get("/groups/{chat_id}/members")
def members(chat_id:uuid.UUID,db:DB,user:UserDep):
    require_member(db,str(chat_id),user.id)
    chat=db.get(Chat,str(chat_id))
    if not chat or chat.type!="group":raise HTTPException(404,"Group not found")
    return [{"user_id":m.user_id,"role":m.role} for m in db.scalars(select(ChatMember).where(ChatMember.chat_id==str(chat_id))).all()]
@router.patch("/groups/{chat_id}")
def rename(chat_id:uuid.UUID,data:GroupRename,db:DB,user:UserDep):
    chat=admin_only(db,str(chat_id),user.id)
    if not data.title.strip():raise HTTPException(422,"Title cannot be blank")
    chat.title=data.title.strip();db.commit()
    return {"id":chat.id,"title":chat.title}
@router.post("/groups/{chat_id}/members",status_code=201)
def add_member(chat_id:uuid.UUID,data:GroupMember,db:DB,user:UserDep):
    admin_only(db,str(chat_id),user.id)
    uid=str(data.user_id)
    if not db.get(User,uid):raise HTTPException(404,"User not found")
    if db.scalar(select(ChatMember).where(ChatMember.chat_id==str(chat_id),ChatMember.user_id==uid)):
        raise HTTPException(409,"Already a member")
    db.add(ChatMember(chat_id=str(chat_id),user_id=uid));db.commit()
    return {"added":True}
@router.delete("/groups/{chat_id}/members/{member_id}",status_code=204)
def remove_member(chat_id:uuid.UUID,member_id:uuid.UUID,db:DB,user:UserDep):
    if str(member_id)!=user.id:admin_only(db,str(chat_id),user.id)
    else:require_member(db,str(chat_id),user.id)
    row=db.scalar(select(ChatMember).where(ChatMember.chat_id==str(chat_id),ChatMember.user_id==str(member_id)))
    if row is None:raise HTTPException(404,"Member not found")
    if row.role=="admin":
        admins=db.scalars(select(ChatMember).where(ChatMember.chat_id==str(chat_id),ChatMember.role=="admin")).all()
        if len(admins)<=1:raise HTTPException(409,"Cannot remove the last administrator")
    db.delete(row);db.commit()
