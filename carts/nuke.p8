pico-8 cartridge // http://www.pico-8.com
version 9
__lua__
local time_t=0
local before_update={c=0}
local after_draw={c=0}

local actors = {} --all actors in world

-- side
local no_side,good_side,bad_side,any_side=0x0,0x1,0x2,0x3
local table_delims={
	['{']="}",
	['[']="]"}
-- register json context here
local _g={
	['true']=true,
	['false']=false,
	no_side=no_side,
	good_side=good_side,
	bad_side=bad_side,
	any_side=any_side,
	nop=function() end
}

-- json parser
-- from: https://gist.github.com/tylerneylon/59f4bcf316be525b30ab
local function error(str)
	printh("error"..str)
	assert()
end

local function match(s,tokens)
	for i=1,#tokens do
		if(s==sub(tokens,i,i)) return true
	end
	return false
end
local function skip_delim(str, pos, delim, err_if_missing)
 if sub(str,pos,pos)!=delim then
  if(err_if_missing) error('expected '..delim..' near position '.. pos)
  return pos,false
 end
 return pos+1,true
end
local function parse_str_val(str, pos, val)
	val=val or ''
	if pos>#str then
		error('end of input found while parsing string.')
	end
	local c=sub(str,pos,pos)
	if(c=='"') return _g[val] or val,pos+1
	return parse_str_val(str,pos+1,val..c)
end
local function parse_num_val(str,pos,val)
	val=val or ''
	if pos>#str then
		error('end of input found while parsing string.')
	end
	local c=sub(str,pos,pos)
	if(not match(c,"-x0123456789.")) return val+0,pos
	return parse_num_val(str,pos+1,val..c)
end
-- public values and functions.

function json_parse(str, pos, end_delim)
	pos=pos or 1
	if(pos>#str) error('reached unexpected end of input.')
	local first=sub(str,pos,pos)
	if match(first,"{[") then
		local obj,key,delim_found={},true,true
		pos+=1
		while true do
			key,pos=json_parse(str, pos, table_delims[first])
			if(key==nil) return obj,pos
			if not delim_found then error('comma missing between table items.') end
			if first=="{" then
				pos=skip_delim(str,pos,':',true)  -- true -> error if missing.
				obj[key],pos=json_parse(str,pos)
			else
				add(obj,key)
			end
			pos,delim_found=skip_delim(str, pos, ',')
	end
	elseif first=='"' then
		-- parse a string (or a global object)
		return parse_str_val(str,pos+1)
	elseif match(first,"-0123456789") then
		-- parse a number.
		return parse_num_val(str, pos)
	elseif first==end_delim then  -- end of an object or array.
		return nil,pos+1
	else  -- parse true, false
		for lit_str,lit_val in pairs(_g) do
			local lit_end=pos+#lit_str-1
			if sub(str,pos,lit_end)==lit_str then return lit_val,lit_end+1 end
		end
		local pos_info_str = 'position ' .. pos .. ': ' .. sub(str, pos, pos + 10)
		error('invalid json syntax starting at ' .. pos_info_str)
	end
end

-- player settings
local plyr
local plyr_playing,plyr_hpmax
local plyr_score
local plyr_acc=0.05
local plyr_frames=json_parse('[[17,18,19,18,17],[33,34,35],[49,50,51]]')
local pause_t=0
-- blast
local blast_frames=json_parse('[192,194,196,198,200,202]')
-- camera
local shkx,shky=0,0
local cam_x,cam_y
-- weapons catalog
local dmg_mask,dmg_types=0xff,json_parse('{"dmg_phys":0x0100,"dmg_contact":0x0200,"dmg_energy":0x0400,"dmg_poison":0x0800}')
local weapons=json_parse('{"base_gun":{"sx":48,"sy":8,"frames":[42,42,42],"dmg_type":"dmg_phys","dmg":1,"spread":0.05,"v":0.1,"ttl":90,"dly":32},"goo":{"frames":[63,63,63],"dmg_type":"dmg_phys","dmg":1,"spread":0.25,"v":0,"ttl":90,"dly":64},"acid_gun":{"frames":[26,27,28],"blts":3,"spread":0.1,"bounce":0.9,"dmg_type":"dmg_poison","dmg":3,"v":0.1,"xy":[1,0],"ttl":30,"dly":5},"uzi":{"n":"uzi","icon":21,"sx":32,"sy":8,"frames":[10,12,11],"spread":0.04,"dmg_type":"dmg_phys","dmg":2,"v":0.4,"ttl":30,"dly":5,"ammo":75,"shk_pow":2},"minigun":{"n":"minigun","icon":25,"sx":64,"sy":8,"frames":[10,12,11],"spread":0.04,"dmg_type":"dmg_phys","dmg":2,"v":0.45,"ttl":30,"blts":1,"dly":3,"ammo":250,"shk_pow":2},"shotgun":{"n":"pump","icon":37,"sx":32,"sy":16,"frames":[10,12,11],"spread":0.05,"blts":3,"dmg_type":"dmg_phys","dmg":2,"inertia":0.95,"v":0.3,"ttl":30,"dly":56,"ammo":25,"shk_pow":2},"glock":{"n":"g.lock","icon":53,"sx":32,"sy":24,"frames":[10,12,11],"spread":0.01,"dmg_type":"dmg_phys","dmg":4,"v":0.5,"ttl":30,"dly":32,"ammo":17,"shk_pow":2},"rpg":{"n":"rpg","icon":23,"sx":48,"sy":8,"actor_cls":"msl_cls","spread":0.02,"v":0.4,"dly":72,"ammo":8,"shk_pow":3},"grenade":{"n":"mortar","icon":55,"sx":48,"sy":24,"actor_cls":"grenade_cls","spread":0.02,"v":0.5,"dly":72,"ammo":12,"shk_pow":2.1},"mega_gun":{"sx":48,"sy":8,"frames":[43,43,43],"dmg_type":"dmg_phys","dmg":5,"spread":0.05,"v":0.1,"ttl":30,"dly":32,"sub_cls":"mega_sub","emitters":5},"mega_sub":{"sx":48,"sy":8,"frames":[26,27,28],"dmg_type":"dmg_phys","dmg":5,"spread":0,"v":0.3,"ttl":30,"dly":5,"burst":5}}')
for k,v in pairs(weapons) do
	if v.dmg then
		v.dmg=bor(dmg_types[v.dmg_type],v.dmg)
	end
	_g[k]=v
end

-- light shader
local shade={}
function scol(i)
	return sget(88+2*flr(i/8)+1,24+i%8)
end
for i=0,15 do
	local c1=scol(i)
	for j=0,15 do
		shade[bor(i,shl(j,4))]=bor(c1,shl(scol(j),4))
	end
end
local lights={}
for r=42,44 do
	local light={}
	for y=0,127 do
		local dy=64-y
		if dy*dy<r*r then
			local x1,x2,x3=flr(sqrt(r*r-dy*dy)/2),0,0
			local r2=0.8*r
			if dy*dy<r2*r2 then
				x2=flr(sqrt(r2*r2-dy*dy)/2)
			end
			r2*=0.8
			if dy*dy<r2*r2 then
				x3=flr(sqrt(r2*r2-dy*dy)/2)
			end
			add(light,{31-x1,31-x2,31-x3})
		else
			add(light,{31,31,31})
		end
	end
	add(lights,light)
end

_g.darken=function()
	local m,r=0x6000,flr(rnd(#lights))+1
	for y=1,128 do
		local l=lights[r][y]
		local x0,x1,x2=l[1],l[2],l[3]
		for x=0,x0 do
			--poke(m+x,shade[shade[peek(m+x)]])
			poke(m+x,0)
			poke(m+63-x,0)
		end
		for x=x0+1,x1 do
			poke(m+x,shade[shade[peek(m+x)]])
			poke(m+63-x,shade[shade[peek(m+63-x)]])
		end
		for x=x1+1,x2 do
			poke(m+x,shade[peek(m+x)])
			poke(m+63-x,shade[peek(m+63-x)])
		end
		m+=64
	end
end

-- modifiers
--[[
	weapon bounce
	reduce fire dly
	multiple bullets
	reduced spread
	reduced damage
	world inertia
]]

-- levels
local active_actors
local cur_level,cur_loop
local levels=json_parse('[{"n":"desert","blast_tile":69,"floors":[68,64,65,67,111],"walls":[66],"shadow":110,"bkg_col":1,"d":3,"cw":32,"ch":32,"w":[4,6],"h":[4,6],"paths":[1,3],"path":{"bends":[1,2],"w":[3,4],"len":[4,8]},"spawn":[[2,4,"sandman_cls"],[1,3,"worm_cls"]]},{"n":"sewers","shader":"darken","floors":[86,87,87,88],"walls":[90,89,91],"shadow":94,"borders":[10,11,3],"bkg_col":3,"d":4,"cw":32,"ch":32,"w":[5,8],"h":[4,6],"paths":[3,4],"path":{"bends":[2,3],"w":[1,2],"len":[6,9]},"spawn":[[1,3,"slime_cls"],[0,1,"barrel_cls"]]},{"n":"snow plains","floors":[70,71,72],"walls":[74],"shadow":95,"blast_tile":75,"borders":[1,12,6],"bkg_col":6,"d":4,"cw":32,"ch":48,"w":[4,6],"h":[4,6],"paths":[2,4],"path":{"bends":[1,2],"w":[2,4],"len":[5,8]},"spawn":[[1,2,"dog_cls"],[0,2,"bear_cls"]]},{"n":"palace","floors":[96,100],"walls":[97,98,99,108],"shadow":101,"borders":[7,0,5],"bkg_col":9,"d":5,"cw":32,"ch":48,"w":[4,6],"h":[4,6],"paths":[1,2],"path":{"bends":[1,2],"w":[1,2],"len":[2,3]}},{"n":"lab","floors":[102,105],"walls":[103,104,106],"shadow":107,"borders":[6,7,5],"bkg_col":5,"d":4,"cw":32,"ch":48,"w":[4,6],"h":[3,5],"paths":[4,4],"path":{"bends":[0,2],"w":[1,2],"len":[8,12]}},{"n":"throne","builtin":true,"bkg_col":0,"borders":[7,0,5],"cx":103,"cy":0,"cw":13,"ch":31,"plyr_pos":{"x":110,"y":28},"spawn":[{"a":"throne_cls","x":109,"y":6},{"a":"ammo_cls","x":106,"y":27},{"a":"ammo_cls","x":107,"y":27},{"a":"ammo_cls","x":106,"y":28},{"a":"ammo_cls","x":107,"y":28},{"a":"health_cls","x":112,"y":27},{"a":"health_cls","x":113,"y":27},{"a":"health_cls","x":112,"y":28},{"a":"health_cls","x":113,"y":28}]}]')

local blts={len=0}
local parts={len=0}
local zbuf={len=0}

local face2unit=json_parse('[[1,0],[0.6234,-0.7819],[-0.2225,-0.9749],[-0.901,-0.4338],[-0.901,0.4338],[-0.2225,0.975],[0.6234,0.7819],[1,0]]')

local face1strip=json_parse('[{"flipx":false,"flipy":false},{"flipx":false,"flipy":false},{"flipx":false,"flipy":false},{"flipx":true,"flipy":false},{"flipx":true,"flipy":false},{"flipx":true,"flipy":false},{"flipx":false,"flipy":false},{"flipx":false,"flipy":false}]')
local face3strip=json_parse('[{"strip":1,"flipx":false,"flipy":false},{"strip":2,"flipx":false,"flipy":false},{"strip":2,"flipx":false,"flipy":false},{"strip":3,"flipx":false,"flipy":false},{"strip":1,"flipx":true,"flipy":false},{"strip":3,"flipx":false,"flipy":false},{"strip":3,"flipx":true,"flipy":false},{"strip":3,"flipx":false,"flipy":false}]')

-- screen manager
local sm_t,sm_cur,sm_next,sm_dly=0,nil,nil,0
function sm_push(s)
	sm_t=0
	if sm_cur then
		sm_dly=sm_t+8
		sm_next=s
		--fade(0,8)
	else
		sm_cur=s
		sm_cur:init()
	end
end
-- futures
function futures_update(futures)
	futures=futures or before_update
	for f in all(futures) do
		local r,e=coresume(f)
		if not r then
			del(futures,f)
		--[[
		else
			printh("exception:"..e)
		]]
		end
	end
end
function futures_add(fn,futures)
	add(futures or before_update,cocreate(fn))
end
-- print text helper
local txt_center,txt_shade,txt_border=false,-1,false
function txt_options(c,s,b)
	txt_center=c or false
	txt_shade=s or -1
	txt_border=b or false
end
function txt_print(s,x,y,col)
	if txt_center then
		x-=flr((4*#s)/2+0.5)
	end
	if txt_shade!=-1 then	
		print(s,x+1,y,txt_shade)
		if txt_border then
			print(s,x-1,y,txt_shade)
			print(s,x,y-1,txt_shade)
			print(s,x,y+1,txt_shade)
		end
	end
	print(s,x,y,col)
end
-- helper
function foreach_update(a)
	local n,c,elt=a.len,0
	a.len=0
	for i=1,n do
		elt=a[i]
		if elt:update() then
			c+=1
			a[c]=elt
		end
	end
	-- avoid mlk
	for i=c+1,n do
		a[i]=nil
	end
	a.len=c
end
function clone(src,dst)
	if(src==dst) assert()
	if(type(src)!="table") assert()
	dst=dst or {}
	for k,v in pairs(src) do
		dst[k]=v
	end
	return dst
end
function nop() end
function lerp(a,b,t)
	return a*(1-t)+b*t
end
function smoothstep(t)
	t=mid(t,0,1)
	return t*t*(3-2*t)
end
function rndrng(ab)
	return flr(lerp(ab[1],ab[2],rnd(1)))
end
function rndarray(a)
	return a[flr(rnd(#a))+1]
end
function rotate(a,p)
	local c,s=cos(a),-sin(a)
	return {
		p[1]*c-p[2]*s,
		p[1]*s+p[2]*c}
end
function bpset(x,y,c)
	local d=bor(0x6000,x)+shl(y,7)
	-- todo: fix (not a ramp!)
	c=sget(min(c,7),8)
	c=bor(c,shl(c,4))
	poke(d,c)
	poke(d+64,c)
end
function rspr(sx,sy,x,y,a)
	local ca,sa=cos(a),sin(a)
 local ddx0,ddy0,srcx,srcy=ca,sa
 ca*=4
 sa*=4
 local dx0,dy0=sa-ca+4,-ca-sa+4
 for ix=0,7 do
  srcx,srcy=dx0,dy0
  for iy=0,7 do
   if band(bor(srcx,srcy),0xfff8)==0 then
   	local c=sget(sx+srcx,sy+srcy)
   	if c!=14 then
   		pset(x+ix,y+iy,c)
  		end
  	end
   srcx-=ddy0
  	srcy+=ddx0
  end
  dx0+=ddx0
  dy0+=ddy0
 end
end
function is_near_actor(a1,a2,r)
	local dx,dy=a2.x-a1.x,a2.y-a1.y
	return dx*dx+dy*dy<r*r
end

-- https://github.com/morgan3d/misc/tree/master/p8sort
function sort(t,n)
	if (n<2) return
 local i,j,temp
 local lower = flr(n/2)+1
 local upper = n
 while 1 do
  if lower>1 then
   lower-=1
   temp=t[lower]
  else
   temp=t[upper]
   t[upper]=t[1]
   upper-=1
   if upper==1 then
    t[1]=temp
    return
   end
  end

  i,j=lower,lower*2
  while j<=upper do
   if j<upper and t[j].key<t[j+1].key then
    j += 1
   end
   if temp.key<t[j].key then
    t[i] = t[j]
    i = j
    j += i
   else
    j = upper + 1
   end
  end
  t[i] = temp
 end
end

-- collision
function circline_coll(x,y,r,x0,y0,x1,y1)
	local dx,dy=x1-x0,y1-y0
	local ax,ay=x-x0,y-y1
	local t,d=ax*dx+ay*dy,dx*dx+dy*dy
	if d==0 then
		t=0
	else
		t=mid(t,0,d)
		t/=d
	end
	local ix,iy=x0+t*dx-x,y0+t*dy-y
	return (ix*ix+iy*iy)<r*r
end
-- zbuffer
function zbuf_clear()
	zbuf.len=0
end
function zbuf_write(obj)
	local xe,ye=cam_project(obj.x,obj.y)
	local ze=obj.z and 8*obj.z or 0
	zbuf.len+=1
	zbuf[zbuf.len]={obj,{xe,ye-ze},key=ye+ze}
end
function zbuf_draw()
	sort(zbuf,zbuf.len)
	for i=1,zbuf.len do
		local o,pos=zbuf[i][1],zbuf[i][2]
		o:draw(pos[1],pos[2])
	end
end

-- collision map
local cmap={}
local cmap_cells={0,1,129,128,127,-1,-129,-128,-127}
function cmap_clear(objs)
	local h,obj
	cmap={}
	for i=1,#objs do
		obj=objs[i]
		if obj.w>0 then
			h=flr(obj.x)+128*flr(obj.y)
			cmap[h]=cmap[h] or {}
			add(cmap[h],obj)
		end
	end
end
function cmap_write(obj)
	local h=flr(obj.x)+128*flr(obj.y)
	cmap[h]=cmap[h] or {}
	add(cmap[h],obj)
end
local cmap_i,cmap_cell,cmap_h
function cmap_near_iterator(x,y)
	cmap_i,cmap_cell=1,1
	cmap_h=flr(x)+128*flr(y)
end
function cmap_near_next()
	if(cmap_cell==nil) assert()
	while(cmap_cell<=9) do
		local h=cmap_h+cmap_cells[cmap_cell]
		local objs=cmap[h]
		if objs and cmap_i<=#objs then
			local obj=objs[cmap_i]
			if(not obj) assert()
			cmap_i+=1
			return obj
		end
		cmap_i=1
		cmap_cell+=1
	end
	return nil
end
function cmap_draw()
	local h=flr(plyr.x)+128*flr(plyr.y)

	for k,v in pairs(cmap) do
		local s=(h==k and "*" or "")
		local x,y=cam_project(k%128,flr(k/128))
		print(s..(#v),x,y,7)
	end
end

-- camera
function cam_shake(u,v,pow)
	shkx=pow*u
	shky=pow*v
end
function cam_update()
	shkx*=-0.7-rnd(0.2)
	shky*=-0.7-rnd(0.2)
	if(abs(shkx)>0.5 or abs(shky)>0.5) camera(shkx,shky)
end
function cam_track(x,y)
	cam_x,cam_y=(x*8)-4,(y*8)-4
end
function cam_project(x,y)
	return 64+8*x-cam_x,64+8*y-cam_y
end

-- special fxs
function update_part(self)
	if(self.t<time_t or self.r<0) return false
	self.x+=self.dx
	self.y+=self.dy
	self.z+=self.dz
	self.dx*=self.inertia
	self.dy*=self.inertia
	self.dz*=self.inertia
	self.r+=self.dr
	zbuf_write(self)
	return true
end
function make_part(x,y,z,src)
	local p={
		x=x,y=y,z=z,
		dx=0,dy=0,dz=0,
		r=1,dr=0,
		inertia=0,
		t=time_t+src.dly,
		update=update_part
	}
	for k,v in pairs(src) do
		p[k]=v
	end
	-- randomize selected values
	if src.rnds then
		for k in all(rnds) do
			p[k]*=(1+0.2*rnd())
		end
	end
	parts.len+=1
	parts[parts.len]=p
	return p
end

_g.update_static_part=function(self)
	if(self.t<time_t or self.r<0) return false
	self.r+=self.dr
	zbuf_write(self)
	return true
end
_g.draw_circ_part=function(self,x,y)
	circfill(x,y,8*self.r,self.c)
end
_g.draw_spr_part=function(self,x,y)
	local sw=self.sw or 1
	pal()
	palt(0,false)
	palt(14,false)
	spr(self.spr,x-4*sw,y-4*sw,sw,sw)
end
_g.draw_txt_part=function(self,x,y)
	local l=2*#self.txt
	print(self.txt,x-l+1,y-2,0)
	print(self.txt,x-l,y-2,7)
end
local all_parts=json_parse('{"flash_part_cls":{"dly":4,"r":0.5,"c":7,"dr":-0.1,"update":"update_static_part","draw":"draw_circ_part"},"smoke_part_cls":{"dly":18,"r":0.3,"dr":-0.01,"c":7,"rnds":["r"],"draw":"draw_circ_part"}}')

-- bullets
function blt_update(self)
	if self.t>time_t then
		local x0,y0=self.x,self.y
		local x1,y1=x0+self.dx,y0+self.dy
		local inertia=self.wp.inertia
		if inertia then
			self.dx*=inertia
			self.dy*=inertia
		end
		local s=solid(x1,y0) or solid(x0,y1) or solid(x1,y1)
		if s then
			-- todo: blt hit wall
			make_part(self.x,self.y,0.25,all_parts.flash_part_cls)
			return false
		end
		
		-- actors hit?
		-- todo:get all hitable actors in range
		for a in all(actors) do
			if (self.side!=a.side or a.side==any_side) and circline_coll(a.x,a.y,a.w,x0,y0,x1,y1) then
				a:hit(self.wp.dmg)
				-- impact!
				a.dx+=self.dx
				a.dy+=self.dy
		
				make_part(self.x,self.y,0.25,{
					dx=1.5*self.dx,
					dy=1.5*self.dy,
					dr=-0.02,
					r=0.4,
					dly=8,
					c=9+rnd(1),
					draw=_g.draw_circ_part
				})			
				return false
			end
		end
		self.prevx,self.prevy=x0,y0
		self.x,self.y=x1,y1
		zbuf_write(self)
		return true
	end
	-- sub bullet?
	local wp=self.wp.sub_cls
	if wp then
		wp=weapons[wp]
		local x,y,side,n=self.x,self.y,self.side,self.wp.emitters
		futures_add(function()
			local ang,dang=0,1/n
			for k=1,wp.burst do
				ang=0
				for i=1,n do
					make_blt({
						x=x,y=y,
						side=side,
						angle=ang},wp)
					ang+=dang
				end
				for i=1,wp.dly do yield() end
			end
		end)
	end
	return false
end
function make_blt(a,wp)
	local n=wp.blts or 1
	for i=1,n do
		if a.ammo then
			if a.ammo<=0 then
				-- todo: click sound
				sfx(3)
				return
			end
			a.ammo-=1
		end
		if wp.sfx then
			sfx(wp.sfx)
		end
		local ang=a.angle+wp.spread*(rnd(2)-1)
		local u,v=cos(ang),sin(ang)
		local b={
			x=a.x+0.5*u,y=a.y+0.5*v,
			wp=wp,
			dx=wp.v*u,dy=wp.v*v,
			side=a.side,
			facing=flr(8*(ang%1))
		}
		if wp.actor_cls then
			make_actor(0,0,
				clone(bad_actors[wp.actor_cls],b))
		else
			clone({
				side=a.side,
				t=time_t+wp.ttl,
				-- for fast collision
				prevx=b.x,prevy=b.y,
				update=blt_update,
				draw=draw_blt},b)
			blts.len+=1
			blts[blts.len]=b
		end
		-- muzzle flash
		if(i==1) make_part(b.x,b.y+0.5,0.5,all_parts.flash_part_cls)
	end
end
function draw_blt(b,x,y)
	palt(0,false)
	palt(14,true)
	local spr_options=face3strip[b.facing+1]
	spr(b.wp.frames[spr_options.strip],x-4,y-4,1,1,spr_options.flipx,spr_options.flipy)
end

-- map
local rooms
local tile_sides=json_parse('[[0,0],[1,0],[0,1],[-1,0],[0,-1]]')

function make_level(lvl)
	-- spawn entities
	active_actors=0
	
	local rules=levels[lvl]
	if rules.builtin then
		for s in all(rules.spawn) do
			make_actor(s.x,s.y,bad_actors[s.a])
		end
	else
		make_rooms(rules)
		-- invalid level
		if(not rules.spawn) print(cur_level.." "..rules.n) assert()
		for i=2,#rooms do
			local r,sp=rooms[i],rndarray(rules.spawn)
			local n=flr(lerp(sp[1],sp[2],rnd()))
			for k=1,n do
				local x,y=r.x+lerp(0,r.w,rnd()),r.y+lerp(0,r.h,rnd())
				make_actor(x,y,bad_actors[sp[3]])
				active_actors+=1
			end
		end
	end
end
function make_rooms(rules)
	rooms={}
	for i=0,rules.cw-1 do
		for j=0,rules.ch-1 do
			mset(i,j,rules.solid_tiles_base)
		end
	end
	local cw,ch=rndrng(rules.w),rndrng(rules.h)
	local cx,cy=rules.cw/2-cw,rules.ch/2-ch
	make_room(
			cx,cy,cw,ch,
			rules.d,
			rules)
	make_walls(0,rules.cw-1,0,rules.ch-1,rules,true)
end
function ftile(cx,cy)
	local c=0
	for i=0,#tile_sides-1 do
		local p=tile_sides[i+1]
		local s=mget(cx+p[1],cy+p[2])
		if s==0 or fget(s,7) then
			c=bor(c,shl(1,i))
		end
	end
	return c
end

function make_walls(x0,x1,y0,y1,rules,shadow)
	local tf,t
	local walls={}
	for i=x0,x1 do
		for j=y0,y1 do
			-- borders
			tf=ftile(i,j)
			if band(tf,1)!=0 then
				tf=shr(band(tf,0xfffe),1)
				t=112+tf
				mset(i,j,t)
				-- south not solid?
				if band(tf,0x2)==0 then
					if rnd()<0.8 then
						t=rules.walls[1]
					else
						t=rndarray(rules.walls)
					end
					add(walls,{i,j+1,t})
				end
			end
		end
	end
	for w in all(walls) do
		mset(w[1],w[2],w[3])
		if(shadow)mset(w[1],w[2]+1,rules.shadow)
	end
end

function make_room(x,y,w,h,ttl,rules)
	if(ttl<0) return
	local r={
		x=x,y=y,
		w=w,h=h}
	r=dig(r,rules)
	if r then
		add(rooms,r)
		local n=ttl*rndrng(rules.paths)
		for i=1,n do
			local a=flr(rnd(4))/4
			local v=rotate(a,{1,0})
			local bends=rndrng(rules.path.bends)
			-- starting point
			local hh,hw=r.w/2,r.h/2
			local cx,cy=r.x+hw,r.y+hh
			x,y=cx+v[1]*hw,cy+v[2]*hh
			make_path(x,y,a,
				bends,ttl-1,rules)
		end
	end
end
function make_path(x,y,a,n,ttl,rules)
	-- end of corridor?
	if n<=0 then
		make_room(
			x,y,
			rndrng(rules.w),
			rndrng(rules.h),
			ttl-1,
			rules)
		return
	end
	local w,h=
		rndrng(rules.path.w),
		rndrng(rules.path.len)
	-- rotate
	local wl=rotate(a,{h,w})
	local c={
		x=x,y=y,
		w=wl[1],h=wl[2]
	}
	-- stop invalid paths
	if dig(c,rules) then
		a+=(rnd(1)>0.5 and 0.25 or -0.25)
		make_path(
			c.x+c.w,c.y+c.h,
			a,n-1,ttl,rules)
	end
end
function dig(r,rules)
	local cw,ch=rules.cw-1,rules.ch-1
	local x0,y0=mid(r.x,1,cw),mid(r.y,1,cw)
	local x1,y1=mid(r.x+r.w,1,ch),mid(r.y+r.h,1,ch)
	x0,x1=min(x0,x1),max(x0,x1)
	y0,y1=min(y0,y1),max(y0,y1)
	cw,ch=x1-x0,y1-y0
	if cw>0 and ch>0 then
		for i=x0,x1 do
			for j=y0,y1 do
				if rnd()<0.9 then
					mset(i,j,rules.floors[1])
				else							
					mset(i,j,rndarray(rules.floors))
				end
			end
		end
		return {x=x0,y=y0,w=cw,h=ch}
	end
	return nil
end
function clear_walls(x,y,rules)
	if fget(mget(x,y),2) then
		local t=rules.floors[1]
		mset(x,y,t)
		mset(x,y+1,t)
	end
end
function dig_blast(x,y)
	local rules=levels[cur_level]	
	clear_walls(x+1,y,rules)
	clear_walls(x-1,y,rules)
	clear_walls(x,y+1,rules)
	for s in all(tile_sides) do
		mset(x+s[1],y+s[2],rules.blast_tile)
	end
	make_walls(x-2,x+2,y-2,y+2,rules,false)
 -- todo: fix walls
end

function solid(x, y)
 return fget(mget(x,y),7)
end

function solid_area(x,y,w,h)

 return 
  solid(x-w,y-h) or
  solid(x+w,y-h) or
  solid(x-w,y+h) or
  solid(x+w,y+h)
end

function lineofsight(x1,y1,x2,y2,dist)
	x1,y1=flr(x1),flr(y1)
	x2,y2=flr(x2),flr(y2)
	local dx=x2-x1
	local ix=dx>0 and 1 or -1
	dx=shl(abs(dx),1)

	local dy=y2-y1
	local iy=dy>0 and 1 or -1
	dy=shl(abs(dy),1)

	if(dx==0 and dy==0) return true
	
	if dx>=dy then
		error=dy-dx/2
 	while x1!=x2 do
   if (error>0) or ((error==0) and (ix>0)) then
	   error-=dx
 	  y1+=iy
			end

 	 error+=dy
 	 x1+=ix
 	 dist-=1
 	 if(dist<0) return false
	if(solid(x1,y1)) return false
 	end
	else
 	error=dx-dy/2

 	while y1!=y2 do
  	if (error>0) or ((error==0) and (iy > 0)) then
  	 error-=dy
  	 x1+=ix
		 end
	
  	error+=dx
  	y1+=iy
			dist-=1
		 if(dist<0) return false
	 	if(solid(x1,y1)) return false
 	end
 end
	return true 
end
-- true if a will hit another
-- actor after moving dx,dy
function solid_actor(a,dx,dy)
	cmap_near_iterator(a.x+dx,a.y+dy)
	local a2=cmap_near_next()
	while a2 do
  if a2 != a then
   local x,y=(a.x+dx)-a2.x,(a.y+dy)-a2.y
   if abs(x)<(a.w+a2.w) and
      abs(y)<(a.h+a2.h)
   then 
    -- collision damage?
    if a2.dmg and band(a.side,a2.side)!=0 and a.hit then
    	a:hit(a2.dmg)
    end
    
    -- moving together?
    -- this allows actors to
    -- overlap initially 
    -- without sticking together    
    if (dx!=0 and abs(x) <
	abs(a.x-a2.x)) then
     local v=a.dx+a2.dy
     a.dx=v/2
     a2.dx=v/2
     return true 
    end
    
    if (dy!=0 and abs(y) <
	abs(a.y-a2.y)) then
     local v=a.dy+a2.dy
     a.dy=v/2
     a2.dy=v/2
     return true 
    end    
   end
  end
	a2=cmap_near_next()
 end
 return false
end

-- checks both walls and actors
function solid_a(a, dx, dy)
	if(solid_area(a.x+dx,a.y+dy,a.w,a.w)) return true
	return solid_actor(a, dx, dy) 
end

-- custom actors
function draw_anim_spr(a,x,y)
	palt(0,false)
	palt(14,true)	
	local i=flr(lerp(1,#a.frames,1-(a.t-time_t)/a.ttl))
	spr(a.frames[i],x-8,y-8,2,2)
end

function plyr_die(self)
	
end

function die_actor(self)
	-- last actor?
	active_actors-=1
	if active_actors==0 then
		-- create portal
		make_actor(self.x,self.y,warp_cls)
	else	
		if rnd()>0.5 then
			make_actor(self.x,self.y,bad_actors.health_cls)
		else
			make_actor(self.x,self.y,bad_actors.ammo_cls)
		end
	end
	--[[
	if self.drop_value then
		local v=flr(rnd(self.drop_value))
		if v>0 then
		make_actor(self.x,self.y,loot[v+1])
		end
	end
	]]
end

function hit_actor(self,dmg)
	self.hit_t=time_t+8
	self.hp-=band(dmg_mask,dmg)
	if not self.disable and self.hp<=0 then
		self.hp=0
	 -- avoid reentrancy
	 self.disable=true
	 if(self.die) self:die()	
		if self.dead_spr then
			make_part(self.x,self.y,0,{
				spr=self.dead_spr,
				dx=self.dx,
				dy=self.dy,
				inertia=0.9,
				dly=900,
				draw=_g.draw_spr_part
			})
		end
		del(actors,self)
	end
end
function make_blast(x,y)
	pause_t=4
	for i=1,3 do
		make_actor(x+0.4*(rnd(2)-1),y+0.4*(rnd(2)-1),{
			w=0.8,
			w=0.8,
			inertia=0,
			bounce=0,
			dmg=bor(dmg_phys,15),
			side=any_side,
			t=time_t+12,
			ttl=12,
			frames=blast_frames,
			draw=draw_anim_spr,
			update=function(a)
				if(a.t<time_t) del(actors,a)
			end,
			hit=nop})
	end
	cam_shake(rnd(),rnd(),3)
	dig_blast(x,y+0.5)
end

-- a-star
function go(x0,y0,x1,y1,fn,cb)
	x0,y0,x1,y1=flr(x0),flr(y0),flr(x1),flr(y1)
	local visited,path={},{}
	for i=1,5 do
		local score,next_tile=32000
		for k=1,7 do
			local tile=face2unit[k]
			local x,y=x0+tile[1],y0+tile[2]
			if not visited[x+64*y] and not solid(x,y) then
				local cur_score=fn(x,y,x1,y1)
				if cur_score<score then
					score,next_tile=cur_score,tile
				end
				visited[x+64*y]=true
				if cb then
					cb(x,y,cur_score)
				end
			end
		end
		if next_tile then
			x0+=next_tile[1]
			y0+=next_tile[2]
			add(path,{x0,y0})
		end
		local dx,dy=x1-x0,y1-y0
		if abs(dx)<=1 and abs(dy)<=1 then
			return path
		end
	end
	return path
end

-- custom actors
warp_cls={
	w=0,
	captured=false,
	frames={92,93},
	draw=nop,
	update=function(self)
	 	dig_blast(self.x,self.y)
		mset(self.x+0.5,self.y+0.5,self.frames[flr(time_t/8)%#self.frames+1])
		if (self.captured) return
		local dx,dy=plyr.x-self.x,plyr.y-self.y
		local d=dx*dx+dy*dy
		if d<4 then
			self.captured=true
			futures_add(function()
				plyr_playing=false
				d=sqrt(d)
				local a=atan2(dx,dy)
				for i=1,90 do
					local dist=lerp(d,0,i/90)
					plyr.x,plyr.y=self.x+dist*cos(a),self.y+dist*sin(a)
					yield()
				end
				plyr_playing=true
				cur_level+=1
				-- loop?
				if cur_level>#levels then
					cur_loop+=1
					cur_level=1
				end
				del(actors,self)

				next_level()
			end)
		end
	end
}
_g.health_pickup=function(self)
	local dx,dy=plyr.x-self.x,plyr.y-self.y
	if abs(dx)<0.5 and abs(dy)<0.5 then
		plyr.hp=min(plyr_hpmax,plyr.hp+2)
		make_part(self.x,self.y,0,{
			dz=0.1,
			inertia=0.91,
			dly=72,
			txt=(plyr.hp==plyr_hpmax) and "max. hp" or "hp+2",
			draw=_g.draw_txt_part})
		del(actors,self)
	end
end
_g.ammo_pickup=function(self)
	local dx,dy=plyr.x-self.x,plyr.y-self.y
	if abs(dx)<0.5 and abs(dy)<0.5 then
		plyr.ammo=min(plyr.wp.ammo,plyr.ammo+10)
		make_part(self.x,self.y,0,{
			dz=0.1,
			inertia=0.91,
			dly=72,
			txt=(plyr.wp.ammo==plyr.ammo) and "max. ammo" or "ammo+10",
			draw=_g.draw_txt_part})
		del(actors,self)
	end
end

_g.npc_rnd_move=function(self)
	if self.wp and self.fire_dly<time_t then				
		if is_near_actor(plyr,self,6) then
			make_blt(self,self.wp)		
			self.fire_dly=time_t+self.wp.dly*(rnd(2)-1)
		end
	end

	--[[if self.move_t<time_t then
		self.dx,self.dy=0.05*(rnd(2)-1),0.05*(rnd(2)-1)
		self.move_t=time_t+8+rnd(8)
	end
	]]
	--[[
	if not self.path then
		self.path=go(self.x,self.y,plyr.x,plyr.y,function(x0,y0,x1,y1)
			local dx,dy=x1-x0,y1-y0
			return dx*dx+dy*dy
		end)
		self.move_t=time_t+60
	end
	if self.move_t>time_t then
		local t=flr(#self.path*(self.move_t-time_t)/60)+1
		local dx,dy=self.x-self.path[t][1],self.y-self.path[t][2]
		local d=dx*dx+dy*dy
		if d!=0 then
			d=sqrt(d)
			self.dx+=dx/d
 		self.dy+=dy/d
		end		
	end
	]]
end
_g.blast_on_hit=function(self,dmg)
	if(band(dmg_types.dmg_contact,dmg)!=0) return
	self.hit_t=time_t+8
	self.hp-=1--band(dmg_mask,dmg)
	if self.hp<=0 then
		make_blast(self.x,self.y)
		del(actors,self)
	end
end
_g.blast_on_touch=function(self)
	make_blast(self.x,self.y)
	del(actors,self)
end
_g.smoke_emitter=function(self)
	if time_t%2==0 then
		make_part(self.x,self.y,0,all_parts.smoke_part_cls)
	end
end
_g.draw_rspr_actor=function(self,x,y)
	local ang=atan2(self.dx,self.dy)
	rspr(self.sx,self.sy,x-4,y-4,1-ang)
end
_g.sandman_update=function(self)
	if self.seek_t<time_t and lineofsight(self.x,self.y,plyr.x,plyr.y,4) then
		self.seek_t=time_t+8+rnd(8)
		local dx,dy=plyr.x-self.x,plyr.y-self.y
		local d=sqrt(dx*dx+dy*dy)
		if(d<0.01) return
		dx/=d
		dy/=d
		local v=0.2
		if d<3 then
			v=-0.1
		end	
		self.dx=v*dx
		self.dy=v*dy
		self.angle=atan2(dx,dy)%1
		self.facing=flr(8*self.angle)
		if self.fire_dly<time_t then				
			make_blt(self,self.wp)		
			self.fire_dly=time_t+self.wp.dly
		end
	elseif self.move_t<time_t then
		self.dx,self.dy=0.05*(rnd(2)-1),0.05*(rnd(2)-1)
		self.move_t=time_t+16+rnd(16)
	end
end
_g.wpdrop_draw=function(self,x,y)
	draw_actor(self,x,y)
	if self.near_plyr_t>time_t then
		draw_txt_part(self,x,y-8)
	end
end
_g.wpdrop_update=function(self)
	local dx,dy=plyr.x-self.x,plyr.y-self.y
	if abs(dx)<0.5 and abs(dy)<0.5 then
		self.near_plyr_t=time_t+30
		if btnp(4) then
			self.near_plyr_t=0
			make_part(self.x,self.y,0,{
				dz=0.1,
				inertia=0.91,
				dly=72,
				txt=self.txt,
				draw=_g.draw_txt_part})
			-- swap weapons
			local wp,ang=plyr.wp,rnd()
			-- todo: fix rentrancy
			make_actor(plyr.x,plyr.y,{
				w=0,
				inertia=0.9,
				btn_t=0,
				near_plyr_t=0,
				draw=_g.wpdrop_draw,
				update=_g.wpdrop_update,
				dx=0.1*cos(ang),
				dy=0.1*sin(ang),
				drop=wp,
				ammo=plyr.ammo,
				spr=wp.icon,
				txt=wp.n})
			-- pick drop
			plyr.wp=self.drop
			plyr.ammo=self.ammo
			del(actors,self)
		end
	end
end
_g.throne_update=function(self)
	
end

bad_actors=json_parse('{"barrel_cls":{"side":"any_side","inertia":0.8,"spr":128,"hit":"blast_on_hit"},"msl_cls":{"side":"any_side","inertia":1.01,"sx":80,"sy":24,"update":"smoke_emitter","draw":"draw_rspr_actor","hit":"blast_on_hit","touch":"blast_on_touch"},"grenade_cls":{"side":"any_side","w":0.2,"h":0.2,"inertia":0.91,"bounce":0.8,"sx":96,"sy":16,"update":"smoke_emitter","draw":"draw_rspr_actor","hit":"blast_on_hit","touch":"blast_on_touch"},"sandman_cls":{"hp":3,"wp":"base_gun","frames":[[4,5,6]],"dead_spr":129,"move_t":0,"drop_value":3,"update":"sandman_update"},"scorpion_cls":{"w":1.8,"h":1.8,"hp":10,"wp":"acid_gun","frames":[[135,137]],"move_t":0,"update":"npc_rnd_move"},"worm_cls":{"palt":3,"w":0.2,"h":0.2,"inertia":0.8,"dmg_type":"dmg_contact","dmg":1,"frames":[[7,8]],"move_t":0,"update":"npc_rnd_move"},"slime_cls":{"w":0.2,"h":0.2,"inertia":0.8,"dmg_type":"dmg_contact","dmg":1,"frames":[[29,30,31,30]],"move_t":0,"update":"npc_rnd_move","wp":"goo"},"dog_cls":{"inertia":0.2,"dmg_type":"dmg_contact","dmg":3,"frames":[[61,62]],"move_t":0,"update":"npc_rnd_move"},"bear_cls":{"inertia":0.2,"dmg_type":"dmg_contact","dmg":2,"frames":[[1,2,3]],"move_t":0,"update":"npc_rnd_move"},"throne_cls":{"w":2,"h":1.5,"hp":300,"palt":15,"inertia":0,"spr":139,"move_t":0,"update":"nop"},"health_cls":{"spr":48,"w":0,"h":0,"update":"health_pickup"},"ammo_cls":{"spr":32,"w":0,"h":0,"update":"ammo_pickup"},"wpdrop_cls":{"w":0,"h":0,"inertia":0.9,"btn_t":0,"near_plyr_t":0,"draw":"wpdrop_draw","update":"wpdrop_update"}}')
for k,v in pairs(bad_actors) do
	if v.dmg then
		v.dmg=bor(dmg_types[v.dmg_type],v.dmg)
	end
end

-- actor
-- x,y in map tiles (not pixels)
function make_actor(x,y,src)
	local a={
		x=x,
		y=y,
		dx=0,
		dy=0,
		frame=0,
		inertia=0.6,
		bounce=1,
		hp=1,
		seek_t=0,
		hit_t=0,
		fire_t=0,
		fire_dly=rnd(16),
		w=0.4,
		h=0.4,
		angle=0,
		facing=0, -- trig order e/n/w/s
		side=bad_side,
		draw=draw_actor,
		die=die_actor,
		hit=hit_actor}
	if src then
		for k,v in pairs(src) do
			a[k]=v
		end
	end
	add(actors,a)
	return a
end

function move_actor(a)
	if a.update then
		a:update()
	end

 -- static? no collision check
	if a.dx==0 and a.dy==0 then
		zbuf_write(a)
		return
	end
	local touch=false
 if not solid_a(a,a.dx,0) then
  a.x+=a.dx
 else
  -- otherwise bounce
  touch=true
  a.dx*=-a.bounce
  sfx(2)
 end

 -- ditto for y
 if not solid_a(a,0,a.dy) then
  a.y+=a.dy
 else
 	touch=true
  a.dy*=-a.bounce
  sfx(2)
 end
 
 if touch and a.touch then
 	a:touch()
 end
 
 -- apply inertia
 a.dx*=a.inertia
 a.dy*=a.inertia
 
 a.frame+=abs(a.dx)*4
 a.frame+=abs(a.dy)*4

 zbuf_write(a)
end

function draw_actor(a,sx,sy)
	if a.safe_t and a.safe_t>time_t and band(time_t,1)==0 then
		return
	end
	
	local sw,sh=max(1,flr(2*a.w+0.5)),max(1,flr(2*a.h+0.5))
	sx,sy=sx-4*sw,sy-4*sh
	-- shadow
	palt(14,true)	
	spr(16,sx,sy+7)
	palt(14,false)	
	-- hit effect
	local tcol=a.palt or 14
	if a.hit_t>time_t then
		memset(0x5f00,0xf,16)
		pal(tcol,tcol)
 	end
 	local s,flipx,flipy=a.spr,false,false
 	if a.frames then
 		local spr_options=(#a.frames==3 and face3strip or face1strip)[a.facing+1]
		local frames=a.frames[spr_options.strip or 1]
		s=frames[flr(a.frame%#frames)+1]
		flipx,flipy=spr_options.flipx,spr_options.flipy
	end
	-- actor
	palt(tcol,true)
	spr(s,sx,sy,sw,sh,flipx,flipy)
	palt(tcol,false)
	pal()
 	palt(0,false)
 	palt(14,true)
	local wp=a.wp
	if wp and wp.sx then
		local u,v=cos(a.angle),sin(a.angle)
		-- recoil animation
		local f=-2*max(0,a.fire_t-time_t)/8
		rspr(wp.sx,wp.sy,sx+4*u+f*u,sy+4*v+f*v,1-a.angle)
	end
	palt(14,false)
end

-- player actor
function make_plyr()
	plyr_score=0
	plyr_playing=true
	plyr_hpmax=8
	plyr=make_actor(18,18,{
		hp=plyr_hpmax,
		side=good_side,
		-- todo: rename to strips
		frames=plyr_frames,
		wp=weapons.uzi,
		ammo=weapons.minigun.ammo,
		safe_t=time_t+30,
		die=plyr_die
	})
	return plyr
end

function control_player()
 if plyr_playing then
		local wp,angle=plyr.wp,plyr.angle
	 -- how fast to accelerate
	 local dx,dy=0,0
	 if(btn(0)) plyr.dx-=plyr_acc dx=-1 angle=0.5
	 if(btn(1)) plyr.dx+=plyr_acc dx=1 angle=0
	 if(btn(2)) plyr.dy-=plyr_acc dy=-1 angle=0.25
	 if(btn(3)) plyr.dy+=plyr_acc dy=1 angle=0.75	
		if(bor(dx,dy)!=0) angle=atan2(dx,dy)
		
		if wp and btn(4) and plyr.fire_dly<time_t then
		 	-- todo: rename recoil
			if plyr.ammo>0 then
				plyr.fire_t=time_t+8
				plyr.fire_dly=time_t+wp.dly
				make_blt(plyr,wp)
				if wp.shk_pow then
					local u=face2unit[plyr.facing+1]
					plyr.dx-=0.05*u[1]
					plyr.dy-=0.05*u[2]
					cam_shake(u[1],u[2],wp.shk_pow)
				end
			end
		elseif plyr.fire_dly<time_t then
			plyr.facing=flr(8*angle)
			plyr.angle=angle
		end
	end	
	-- play a sound if moving
	-- (every 4 ticks)
 
 if (abs(plyr.dx)+abs(plyr.dy)>0.1 and (time_t%4)==0) then
  sfx(1)
 end 
 
 cam_track(plyr.x,plyr.y)
end

function next_level()
	actors={}
	make_level(cur_level)
	add(actors,plyr)
	
	local lvl=levels[cur_level]
	if lvl.builtin then
		plyr.x,plyr.y=lvl.plyr_pos.x+0.5,lvl.plyr_pos.y+0.5
	else
		local r=rooms[1]
		plyr.x,plyr.y=r.x+r.w/2,r.y+r.h/2
	end
	plyr.fire_t=0
	plyr.hit_t=0
	plyr.safe_t=time_t+30
	cam_track(plyr.x,plyr.y)
end

function spawner(n,src)
	for i=1,n do
		local x,y=0,0
		local ttl=5
		while(solid(x,y) and ttl>0) do
			x,y=flr(rnd(16)),flr(rnd(16))
			ttl-=1
		end
		if(ttl<0) return
		-- found empty space!
		make_actor(x+0.5,y+0.5,src)
	end
end

-- game loop
function _update60()
	time_t+=1
	futures_update(before_update)
	
	pause_t-=1
	if(pause_t>0) return
	pause_t=0
	
	-- todo: update vs clear
	cmap_clear(actors)
	zbuf_clear()
	control_player(plyr)
	
	foreach(actors,move_actor)
	foreach_update(blts)
	foreach_update(parts)
	cam_update()
end

function _draw()
	local lvl=levels[cur_level]
 	cls(lvl.bkg_col)
	local cx,cy=lvl.cx or 0,lvl.cy or 0
	local sx,sy=64-cam_x+8*cx,64-cam_y+8*cy-4
	map(cx,cy,sx,sy,lvl.cw,lvl.ch,1)
	zbuf_draw()
	palt()
 
	if lvl.borders then
		pal(10,lvl.borders[1])
		pal(9,lvl.borders[2])
		pal(1,lvl.borders[3])
	end
 	map(cx,cy,sx,sy,lvl.cw,lvl.ch,2)
	pal()
			
	if(lvl.shader) lvl.shader()
	--[[
	local a=actors[2]
	local path=go(plyr.x,plyr.y,a.x,a.y,function(x0,y0,x1,y1)
		local dx,dy=x0-x1,y0-y1
		return dx*dx+dy*dy
	end)
	for p in all(path) do
		local xe,ye=cam_project(p[1],p[2])
		spr(0,xe,ye)
	end
	local xe,ye=cam_project(a.x,a.y)	
	circfill(xe,ye,3,8)
	]]
	
	futures_update(after_draw)	

	rectfill(1,1,34,9,0)
	rect(2,2,33,8,6)
	local hp=max(0,plyr.hp)
	rectfill(3,3,flr(32*hp/plyr_hpmax),7,8)
	txt_options(false,0)
	txt_print(hp.."/"..plyr_hpmax,12,3,7)

	palt(14,true)
	palt(0,false)
	spr(plyr.wp.icon,2,10)
	txt_print(plyr.ammo,14,12,7)
end
function _init()
	cls(0)
	cur_level,cur_loop=1,1
	plyr=make_plyr()
	next_level()
end


__gfx__
00000000e000000ee0000000e000000ee000000ee000000ee000000e3333333333333333eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000000ee000000ee000000e
000000000676767006676760056676700f66ff600f66ff600f66ff603333333333333333e00e00eeeeeeeeeeeee99eeeeeeeeeee01111a10011111a001111110
0070070007989860057989800657989005585850055858500558585033333333333333330880870eee9999eeee9aa9eeeee99eee01c00000011c00000111c000
000770000694047006694040056694000ff66ff00ff66ff00ff66ff033300033333333330288820ee999aa9eee9aa9eeee9aa9ee0ccc0c000cccc0c00ccccc00
0007700007676760057676700657676006ff66f006ff66f006ff66f0330fef0333000033e02820eee999aa9eee9999eee99aa9ee0cccccc00cccccc00cccccc0
007007000444444004444440044444400f66f6600f66f6600f66f660330e0e0330efef03ee020eeeee9999eeee9999eee9999eee055556500555556005555550
0000000005000050e050010ee005100ee06f0ff0e006f0f00f006f0e30ef0fe00ef00fe0eee0eeeeeeeeeeeeeee99eeeee99eeee07000070e070070ee006700e
00000000000ee000e000000eeee00eeeee00e00eeee00e0ee0ee00ee3300300330033003eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0eeee0eee0ee0eeeee00eee
e111111eee00000eee00000eee00000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00eeeeeeeeeeeeee00eee
11111111e0999aa0e09999a0e0999990eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee000eeeee777eeeeeeeeeeeeeeee33eeeeeeeeeeeee0370eeee0000eeee0370ee
e111111e099414100999414009999410eeeeeeeeeeeeeeeee0000000e77777770bb0000070077777ee3773eeee3773eeeee377eee03bb70ee03bb70eee0370ee
eeeeeeee094444400994444009994440ee00000eee77777ee0b333b0e700000703b6606070000707e377773eee7777eeee3777eee03bbb0e03bbbb70ee03b0ee
eeeeeeee044455500444455004444450ee000eeeee707eeee0113110e70000070335505070000707e377773eee7777eeee7773eee03bbb0e03bbbbb0ee03b0ee
eeeeeeee0333bab003333ba0033333b0eee0eeeeeee7eeeee0000000e77777770550000070077777ee3773eeee3773eeee773eee03bbbbb003bbbbb0e03bbb0e
eeeeeeee05000050e050050ee005500eeee0eeeeeee7eeeeeeeeeeeeeeeeeeee0660eeee7007eeeeeeeeeeeeeee33eeeeeeeeeee03bbbbb003bbbbb003bbbbb0
eeeeeeeee0eeee0eee0ee0eeeee00eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000eeee7777eeeeeeeeeeeeeeeeeeeeeeeeeeee000000000000000000000000
ee00000eee0000eeee0000eeee0000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee3333eeeeeeeeeee000000ee000000ee000000e
e0bbbbb0e0999a0ee099aa0ee0999a0eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee377773eee00eeee022898900228898002288890
e0777770099999a009999aa0099999a0ee000000ee777777eeee0e0eeeee7e7eeeeeeeeeeeeeeeeeeeeaaeee37777773e0e00eee0228a8a002288a80022888a0
e0373730099999a009999aa0099999a0e0496660e7000007ee001010ee770707e0000000e7777777eea77aee37777773ee0670ee022888800228888002288880
e0353530044444400444444004444440e0445550e7000007e055c1c0e70000070046666077000007eea77aee37777773ee0560ee022767600228767002288760
e033333003333bb00333bbb003333bb0e0400000e7077777e0501010e70707070410000070077777eeeaaeee37777773eee00eee022686800228686002288680
e0533350050000500500000000000050ee0eeeeeee7eeeeeee0e0e0eee7e7e7ee00eeeeee77eeeeeeeeeeeeee377773eeeeeeeee02000020e020010ee002100e
ee00000ee0eeee0ee0eeeeeeeeeeee0eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee3333eeeeeeeeee00eeee00ee0ee0eeeee00eee
ee00000eee0000eeee0000eeee0000eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000eeeeeeee00820000e00ee00ee0e0eeeee0e0eeeeeeeeeeee
e0666660e0999a0ee0999a0ee0999a0eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000ee88eeee1094000004900490090900ee0909000eeeeeeeee
e0777770094141a0091414a0094141a0ee00000eee77777eee000000ee7777770000000000000000e000000e21a90000044848400dd8480e0dd84540eeeeeeee
e0dd8dd0094444900944449009444490e076670ee700007ee03bb660e70000070000000000000000e088777031b30000044909400d4454400d447070eeeebbee
e0d888d0044555400455544004455540e055000ee700777e0453b000700007770000000000000000e055667045c10000044444400447070e0441110eeebbbbbe
e0d686d0033babb00339bbb0033babb0e050eeeee707eeee04400eee70077eee0000000000000000e000000e51d1000004444440044444400447070eee3bbb3e
e0dd6dd005000050000000b003000000ee0eeeeeee7eeeeee00e0eeee77e7eee0000000000000000ee88eeee65e20000050000500404004004044440eee333ee
e0000000e0eeee0eeeeeee0ee0eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0000000000000000eeeeeeee76fd0000e0eeee0ee0e0ee0ee0e0000eeeeeeeee
444444444444444404040404444444444444444444444444777777777777777777777677777677775c775c5c76666667dddddddddddddddd121212eed2dddddd
44444444449944444040404044444444444444444940044077777777777777777667777777657777ccc7c7c565151516ddddddddd1eddddd21ee21de20ddd2ed
44b4b4444549544404040404494444444444444450450945777777777766667775577777765777771cc7c77c71515177ddddddddd11ddddd11dde212ddd0d02d
435b5344445544444040404045444494444444440444504477777777765555777777777675677777c111ccc565151777dddddddddddddddd21dde121dd02dd0d
453535444444444404040404444444544444444445094544777777777555556777777777775677775c5cc77c51515667ddddddddddddeedd12111212d02d0ddd
44555444444444444040404044494444444444444450949477777777775555577777677777657777c5c5c1c775151557ddddddddddd12e1d2121de21dd0dd0dd
44444444444444440404040444454444444444444440040477777777777755577777777777577777515c7ccc77515717dddddddddddd11dd12121d12d2dd02d0
44444444444444444040404044444444444444440445544477777777777777777777777777777777c115c7c577777777dddddddddddddddd2121212100dd2ddd
e2e2e2e22e2e2e2e11111111555555555555555566666666555555555555555556666665375555753131313135353535ee2222eeeeeeeeee1111111111111111
1111111e1111111211111111050505050505050566666566555555555555554560000006567777631313131353777753e2eeee2eee2222ee5151515171717171
12e2e2121e2e2e1e1d1d1d1d0000000000000000666666665555555555555555633333363566665531313131370000752ee22ee2e2eeee2e1515151517171717
1e111e1e12111212dddddddd0000000000000000665666665555555555555555655555565355555313131313560000632e2ee2e2e2e22e2e5555555577777777
121212121e1e1e1edddddddd0055550000000000666666665555555554455555633333363755557531313131362220652ee22ee2e2eeee2e5555555577777777
1e1e2e1e1212e212dddddddd005005000000000066666666555555555445555565555556567777631313131355eee653e2eeee2eee2222ee5555555577777777
121111121e11111edddddddd005005000005500066666566555555555555545576666667356666553131313135225535ee2222eeeeeeeeee5555555577777777
1e2e2e2e12e2e2e2dddddddd005005000005500066666666555555555555555557777775535555531313131353225353eeeeeeeeeeeeeeee5555555577777777
666166669995999999000009906000606660666600000000dddd11116666666667676666ddddd11d6dddddd65555555599959999999599995555555544444444
661516664495444440445440402222206605066611010111dddd11116555555665656666dddd11116dd77dd6111100004aaaa774449544445555555544444444
615551665555555550095900508000806666666610111011dddd11116000000665656666dddd11116d7667d6111100005acccc75555555555454545447444744
155555169999959990440440908080800066606655555556dddd111160b0280665656666dddd111d6d6666d6dddd11119a333ca9999995994444444441676144
6555556644449544409565904088888065600566655555661111dddd6000000665656666d1dddddd6d5665d61111dddd4a3333a4444495444444444444777444
6655566655555555500454005088088066655666665556661111dddd6677776665656666111ddddd6dd55dd61111dddd5aaaaaa5555555554444444444161444
6665666699959999909959909020502066656666666566661111dddd66666666656566661111dddd6dddddd61111dddd92212229999599994444444444444444
6666666644954444400000004001110066666666666666661111dddd6666666660606666dd1ddddd667777661111dddd44954444449544444444444444444444
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa9111111991111111911111199111111111111119111111111111111911111111
a111111aa1111111a111111aa11111111111111a111111111111111a111111119111111991111111911111199111111111111119111111111111111911111111
91111119911111119111111991111111111111191111111111111119111111119111111991111111911111199111111111111119111111111111111911111111
91111119911111119111111991111111111111191111111111111119111111119111111991111111911111199111111111111119111111111111111911111111
91111119911111119111111991111111111111191111111111111119111111119111111991111111911111199111111111111119111111111111111911111111
91111119911111119111111991111111111111191111111111111119111111119111111991111111911111199111111111111119111111111111111911111111
91111119911111119111111991111111111111191111111111111119111111119111111991111111911111199111111111111119111111111111111911111111
99999999999999999111111991111111999999999999999911111119111111119999999999999999911111199111111199999999999999991111111911111111
eeeeeeeeeeeeeeee0000000055555555555555555555555000555555eeeee00000eeeeeeeeeeeee00000eeeefffffffffffff00000000fffffaaffff00000000
ee0000eee0eeeeee0000000055555550005555555555550eee055555eeee02121200eeeeeeeeee02121200eeffffffffffff0666576660ffff99ffff00000000
e07bb70e0800e0ee000000005555550eee05555555555502e2055555eee0700212110eeeeeeee0700212110effff0000ffff0666666660ffff88ffff00000000
e0b77b0e0028080e0000000055555502e20555555555550070055555eeee0ee0000220eeeeeeee0ee0002220fff0eee70fff0777777770ffff00ffff00000000
e03bb30e080282000000000055555500700555555555550101055555eeeeeeeeeee010eeeeeeeeeeeee011200002eee7e0000555555550000000000000000000
e0b77b0e086000f00000000055555501010555555555550111055555eeeeeeee0002210eeeeeeeee000222100c02eee7e0cc0555555550cccc00ccc000000000
e03bb30e02f6ff600000000055555011111055555555501111105555eeeeeee02211220eeeeeeee02211220e0c02eee7e0cc0555555550ccc0000cc000000000
ee0000eee000000e0000000055000122122100555550012222210005eeee0001122210eeeeee0001122210ee0c02eee7e0cc0066666600cc060060c000000000
0000e000000000000000000050222211111222055502221111122220eee01122212000eeeee0112221200eee0c02eee7e0ccc06655660ccc071170c000000000
0b700bb0000000000000000055000122222100205020012222210005ee0822220002220eee082222000220ee0c02eee7e0cc0665bb5660cc057750c000000000
0bb0bb300000000000000000502221eeeee12205550221eeeee12220ee02282002200020ee022820022020ee0c020000e0cc066bbbb660cc055550c000000000
0bbbb30e00000000000000005500028fef8200205020028fef820005e070202020022001e07020202020020e0c00222200cc066bbbb660cc055550c000000000
0bbbbb0e000000000000000050222122f221220555022122f2212220ee00700102002011ee0070002020101e0c02222220ccc06666660ccc100001c000000000
03b03bb0000000000000000050200070007000205020007000700020ee1101111020011eee1101020102011e0c02200220cc1100000011ccc1111cc000000000
033003b0000000000000000055011101110110205020110111011105e111111111011eeee1111110111011ee0c00000000cc1105555011ccccccccc000000000
0000e000000000000000000055551111111111055501111111111555eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee0cc111111cccc11000011cccccccccc000000000
eee0ee0eeeee0eeeee0ee0eeeeeeee0000eeeeee00000000000000000000000000000000eeeeeeb37beeeeee0cccccccccccccc1111cccccccccccc000000000
e00b00b00000b00ee0b00b0eeeeee0cccc0eeeee00000000000000000000000000000000eeeeeb3bb7beeeee0777777777777777777777777777777000000000
0b0b0bb00bb0b0b00bbb0b0eeeee0cccccc0eeee00000000000000000000000000000000eeeeb3bbbb7beeee0111111111111111111111111111111000000000
0bbbbbb00bbbbbb00bbbbbb0ee00ccccc7cc00ee00000000000000000000000000000000eeeeb3bbbb7beeee0111111111111111111111111111111000000000
0bbb33300bbbb3300bbbbb30e066cccccc7c660e00000000000000000000000000000000eeeb3bbbbbb7beee0111111111111111111111111111111000000000
0bbbbbb00bbbbbb00bbbbbb0066ccccccc7cc66000000000000000000000000000000000eeeb3bbbbbb7beee0000000000000000000000000000000000000000
0b0000b0e0b0030e000b30000661cccccccc166000000000000000000000000000000000eeeb3bbbbbb7beeeffffffffffffffffffffffffffffffff00000000
00eeee00ee0ee0eeeee00eee076611cccc11667000000000000000000000000000000000eeeb3bbbbbb7beeeffffffffffffffffffffffffffffffff00000000
eeeeeeeeeeeeeeee00000000076666111166667000000000000000000000000000000000eeeb3bbbbbb7beeeffffffffffffffffffffffffffffffff00000000
eeeeeeee0000000000000000057666666666675000000000000000000000000000000000eeeb3bbbbbb7beeeffffffffffffffffffffffffffffffff00000000
0eeeeeee0000000000000000055777777777755000000000000000000000000000000000eeeb3bbbbbb7beeeffffffffffffffffffffffffffffffff00000000
e0eee0ee0000000000000000e05555555555550e00000000000000000000000000000000eeeb3bbbbbb7beeeffffffffffffffffffffffffffffffff00000000
0ee00f0e0000000000000000e05555555555550e00000000000000000000000000000000eeeb3bbbbbb7beeeffffffffffffffffffffffffffffffff00000000
0e05580e0000000000000000ee055555555550ee00000000000000000000000000000000eeeb3bbbbbb7beeeffffffffffffffffffffffffffffffff00000000
e05555500000000000000000eee0000000000eee00000000000000000000000000000000eeeb3bbbbbb7beeeffffffffffffffffffffffffffffffff00000000
ee00000e0000000000000000eeeeeeeeeeeeeeee00000000000000000000000000000000eeeb3bbbbbb7beeeffffffffffffffffffffffffffffffff00000000
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000000000000000000000000000000
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee1eeeeeeeeeee00000000000000000000000000000000
eeeeeeeeeeeeeeeeeeeee777777eeeeeeeeeeeeeeeeeeeeeeeee9999eeeeeeeeeeee1111eeeeeeeeeeeee1eeeeeeeeee00000000000000000000000000000000
eeeeeee00eeeeeeeeee7777777777eeeeeeeeeeeeeeeeeeeeee9aaa99eeeeeeeeee199911eeeeeeeee11eeeeeeeeeeee00000000000000000000000000000000
eeeee000000eeeeeeee7777777777eeeeeeeee9999eeeeeeee9aa7799999eeeeee199aa111111eeeee1eeeeeeeeeeeee00000000000000000000000000000000
eeee00000000eeeeee777777777777eeeeeee9aaa99eeeeeee9a79999aaa9eeeee19a111111991eeeeee1eeeeeeeeeee00000000000000000000000000000000
eeee00000000eeeeee777777777777eeeeee9aa77999eeeeee9a7999977aa9eeee19a111e11aa91eeeeeeeeee1eee1ee00000000000000000000000000000000
eee0000000000eeeee777777777777eeeeee9a799999eeeeee9999999997a9eeee1111eeeee1a91eeeeee1e11eeeeeee00000000000000000000000000000000
eee0000000000eeeee777777777777eeeeee9a799999eeeeeee999999997a9eeeee111eeeeeee91eeeeeeee11e11eeee00000000000000000000000000000000
eeee00000000eeeeee777777777777eeeeee99999999eeeeeee9a799999999eeeee1911eeeeee11eeeee1eeeee11eeee00000000000000000000000000000000
eeee00000000eeeeee777777777777eeeeeee999999eeeeeeee9a79999999eeeeee19a11eeee11eeeeeeeeeeeeeeeeee00000000000000000000000000000000
eeeee000000eeeeeeee7777777777eeeeeeeee9999eeeeeeeee9aa779999eeeeeee119aa11e11eeeee1eeee1eeeee1ee00000000000000000000000000000000
eeeeeee00eeeeeeeeee7777777777eeeeeeeeeeeeeeeeeeeeeee9aaa99eeeeeeeeee11111eeeeeeeee11eeeeeeeeeeee00000000000000000000000000000000
eeeeeeeeeeeeeeeeeeeee777777eeeeeeeeeeeeeeeeeeeeeeeeee9999eeeeeeeeeeee111eeeeeeeeeeee1eeeeeeeeeee00000000000000000000000000000000
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000000000000000000000000000000
eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee00000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

__gff__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001010501010101010101050101010501010101828201010101050505010101010105050501030101010101010501010182828282828282828282828282828282
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0000000000000000000000000000000045454545454500007f7f7f7f7f7f7f7f7f7f7f7f7f7f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7f7f7f7f7f7f7f7f7f7f7f7f7f0000000000000000000000
005c5c5c5c5c5c5c5c5c5c5c5c00000045515151454500007f7f7d7d7d7d7d7d7d7d7d7d7f7f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7f7d7d7d7d7d7d7d7d7d7d7f7f0000000000000000000000
004e4e4e4e4e4e4e4e4e4e4e4e00010050424242524500007f7f636161616161616161637b7f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e636161616161616161637b7f0000000000000000000000
004c4c4c4c85864c4c4c4c010101010060434343524500007f7e656565656565656565657b7f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e656565656565656565657b7f0000000000000000000000
004c3d4c4c95964c4c4d2d010100000042444444524500007f7e6460608b8c8d8e6060607b7f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e606460646060606460607b7f0000000000000000000000
004c4c4d4c4c4d4c4c4c014c4c00000043444444524500007f7e6060609b9c9d9e6060607b7f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e646060646060606060607b7f0000000000000000000000
0000000000000000000000000000000044444444524500007f7e606060abacadae6060607b7f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e606060606060606060607b7f0000000000000000000000
0000000000000000000000000000000044444444524500007f7e606060606060606060607b7f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e606060646460606060607b7f0000000000000000000000
5044444444444444444463535362444444444444524500007f7e606060606060606060607b7f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e606060606060606060607b7f0000000000000000000000
5044444444444441635345454560444144444444524500007f7e606064606060606060607b7f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e606060606060606060607b7f0000000000000000000000
5044444440444444615151516042404444444444524500007f7e606460646060606060607b7f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e606064606060606060607b7f0000000000000000000000
5044444444444444424242424243444444444444524500007f7e606060606060606060647b7f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e606460646060606060607b7f0000000000000000000000
5044444444444444434343434344444444444444524500007f7e606060606060606060607b7f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e606060606060606060647b7f0000000000000000000000
5044444444444444444444444444444444444444524500007f7e606060606060606060607b7f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e606060606060606060607b7f0000000000000000000000
5044444444444444444444444444446362444444524500007f7e606060606060606060607b7f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e606060606060606060607b7f0000000000000000000000
5044444463535353536244444444446160444444524500007f7e606060606060606060607b7f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e606060606060606060607b7f0000000000000000000000
5044444461514545456044444444444242444444524500007f7f777777777777777777777f7f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e606060606060606060607b7f0000000000000000000000
5044444442426151604244444444444343444444524500007f7f7f7f7f7f7f7f7f7f7f7f7f7f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e646060646060606060607b7f0000000000000000000000
504444444343424242434444444444444444444452450000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e606060606060606060607b7f0000000000000000000000
504444444444434343444444444444444444444452450000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e606060646460606060607b7f0000000000000000000000
455353535353535353535353535353535353535345450000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e606060606060606060607b7f0000000000000000000000
454545454545454545454545454545454545454545450000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e646060646060606060607b7f0000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e606060606060606060607b7f0000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e606060646460606060607b7f0000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e646060646060606060607b7f0000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e606060606060606060607b7f0000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e646060646060606060607b7f0000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e606060606060606060607b7f0000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e606060646460606060607b7f0000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7e606060606060606060607b7f0000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7f777777777777777777777f7f0000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007f7f7f7f7f7f7f7f7f7f7f7f7f7f0000000000000000000000
__sfx__
0001000025550215502355027550295502b5500000000000000000000027550000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344
00 41424344

