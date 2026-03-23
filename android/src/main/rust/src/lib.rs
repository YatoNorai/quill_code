// android/src/main/rust/src/lib.rs
//
// quill_perf — ALL performance-critical helpers for the Quill Code editor.
// #![no_std] staticlib → zero external deps, minimal binary size.
//
// 1. quill_extract_blocks    — O(n) block/fold detection
// 2. quill_search            — literal/whole-word search
// 3. quill_build_line_starts — byte-offset table
// 4. quill_max_line_length   — O(n) max scan
// 5. quill_bracket_match     — bracket pair finder (replaces O(col^2) Dart)
// 6. quill_fulltext_join     — join lines into single buffer (replaces StringBuffer)
// 7. quill_tokenize_line     — regex-free per-line tokenizer
// 8. quill_symbol_scan       — class/func/var declaration scanner

// Android has full std — no_std is unnecessary and requires a custom panic handler.
use std::{slice, ptr};

// ────────────── shared helpers ─────────────────────────────────────────────
#[inline(always)] fn is_word(b: u8) -> bool { b.is_ascii_alphanumeric() || b == b'_' }
#[inline(always)] fn is_upper(b: u8) -> bool { b >= b'A' && b <= b'Z' }
#[inline(always)] fn is_digit(b: u8) -> bool { b >= b'0' && b <= b'9' }
#[inline(always)] fn to_lower(b: u8) -> u8 { if b>=b'A'&&b<=b'Z' {b+32} else {b} }
#[inline(always)] fn is_blank(l: &[u8]) -> bool { l.iter().all(|&b| b==b' '||b==b'\t') }
#[inline(always)] fn leading_sp(l: &[u8]) -> usize {
    let mut n=0; for &b in l { match b {b' '=> n+=1,b'\t'=> n+=2,_=> break} } n
}
#[inline(always)] fn skip_ws(l:&[u8],s:usize)->usize { let mut i=s; while i<l.len()&&(l[i]==b' '||l[i]==b'\t'){i+=1} i }
#[inline(always)] fn word_end(l:&[u8],s:usize)->usize { let mut i=s; while i<l.len()&&is_word(l[i]){i+=1} i }
#[inline(always)] fn sw(h:&[u8],n:&[u8])->bool { h.len()>=n.len()&&&h[..n.len()]==n }

// ══════════════════════════════════════════════════════════════════════════
// 1. quill_extract_blocks
// ══════════════════════════════════════════════════════════════════════════
fn detect_tab(lines:&[&[u8]])->usize{
    let mut t=8usize;
    for l in lines { let s=leading_sp(l); if s>0&&s<t{t=s;} }
    if t<1||t>8{2}else{t}
}
#[no_mangle]
pub unsafe extern "C" fn quill_extract_blocks(
    lp:*const*const u8, ll:*const i32, lc:i32, out:*mut i32, cap:i32
)->i32{
    if lp.is_null()||ll.is_null()||out.is_null()||lc<=0||cap<3{return -1;}
    let n=lc as usize; let bc=(cap as usize)/3; let an=n.min(4096);
    let mut la:[&[u8];4096]=[&[];4096];
    for i in 0..an {
        let p=*lp.add(i); let l=*ll.add(i);
        la[i]=if p.is_null()||l<0{&[]}else{slice::from_raw_parts(p,l as usize)};
    }
    let lines=&la[..an]; let tab=detect_tab(lines);
    let mut sl:[i32;512]=[-1;512]; let mut sc:[u8;512]=[0;512]; let mut sp=0usize;
    let mut rs:[i32;1024]=[0;1024]; let mut re:[i32;1024]=[0;1024]; let mut ri:[i32;1024]=[0;1024]; let mut rc=0usize;
    for i in 0..an {
        let ln=lines[i]; if is_blank(ln){continue;}
        let mut s1=false; let mut s2=false; let mut tpl=false;
        let mut j=0usize;
        while j<ln.len() {
            let c=ln[j];
            if !s1&&!s2&&!tpl&&c==b'/'&&j+1<ln.len()&&ln[j+1]==b'/'{break;}
            if !s1&&!s2&&!tpl {
                match c {
                    b'\'' =>s1=true, b'"' =>s2=true, b'`' =>tpl=true,
                    b'{' |b'(' =>{if sp<512{sl[sp]=i as i32;sc[sp]=c;sp+=1;}}
                    b'}' |b')' =>{
                        let w=if c==b'}'{b'{'} else{b'('};
                        let mut k=sp;
                        while k>0 { k-=1; if sc[k]==w {
                            let s=sl[k] as usize;
                            if i>s&&rc<1024{rs[rc]=s as i32;re[rc]=i as i32;ri[rc]=(leading_sp(lines[s])/tab) as i32;rc+=1;}
                            for m in k..sp-1{sl[m]=sl[m+1];sc[m]=sc[m+1];}
                            sp-=1; break;
                        }}
                    }
                    _=>{}
                }
            } else {
                match (s1,s2,tpl) {
                    (true,_,_)=>if c==b'\'' &&(j==0||ln[j-1]!=b'\\'){ s1=false;}
                    (_,true,_)=>if c==b'"' &&(j==0||ln[j-1]!=b'\\'){ s2=false;}
                    (_,_,true)=>if c==b'`'{ tpl=false;}
                    _=>{}
                }
            }
            j+=1;
        }
    }
    for i in 1..rc { let mut k=i; while k>0 {
        let go=rs[k-1]>rs[k]||(rs[k-1]==rs[k]&&(re[k-1]-rs[k-1])<(re[k]-rs[k]));
        if go{rs.swap(k-1,k);re.swap(k-1,k);ri.swap(k-1,k);k-=1;}else{break;}
    }}
    let w=rc.min(bc);
    for i in 0..w { ptr::write(out.add(i*3),rs[i]); ptr::write(out.add(i*3+1),re[i]); ptr::write(out.add(i*3+2),ri[i]); }
    w as i32
}

// ══════════════════════════════════════════════════════════════════════════
// 2. quill_search
// ══════════════════════════════════════════════════════════════════════════
fn is_wc(b:u8)->bool{b.is_ascii_alphanumeric()||b==b'_'}
fn lit_search(txt:&[u8],pat:&[u8],cs:bool,ww:bool,out:&mut[i32])->usize{
    let n=txt.len(); let m=pat.len(); if m==0||n<m{return 0;}
    let cap=out.len()/2; let mut cnt=0; let mut i=0;
    'outer: while i+m<=n {
        let mut ok=true;
        for k in 0..m {
            let tc=if cs{txt[i+k]}else{to_lower(txt[i+k])};
            let pc=if cs{pat[k]}else{to_lower(pat[k])};
            if tc!=pc {
                let bad=tc; let mut skip=m-k;
                for bk in (0..k).rev(){ let pb=if cs{pat[bk]}else{to_lower(pat[bk])};
                    if pb==bad{let d=k-bk;if d<skip{skip=d;}break;}}
                i+=if skip==0{1}else{skip}; ok=false; break;
            }
        }
        if !ok{continue 'outer;}
        let end=i+m;
        if ww&&((i>0&&is_wc(txt[i-1]))||(end<n&&is_wc(txt[end]))){i+=1;continue;}
        if cnt<cap{out[cnt*2]=i as i32;out[cnt*2+1]=end as i32;}
        cnt+=1; i=end; if cnt>=cap*2{break;}
    }
    cnt
}
#[no_mangle]
pub unsafe extern "C" fn quill_search(
    tp:*const u8,tl:i32,pp:*const u8,pl:i32,fl:i32,out:*mut i32,oc:i32
)->i32{
    if tp.is_null()||pp.is_null()||out.is_null()||tl<0||pl<=0||oc<2{return -1;}
    let t=slice::from_raw_parts(tp,tl as usize);
    let p=slice::from_raw_parts(pp,pl as usize);
    let o=slice::from_raw_parts_mut(out,oc as usize);
    lit_search(t,p,(fl&1)!=0,(fl&2)!=0,o) as i32
}

// ══════════════════════════════════════════════════════════════════════════
// 3. quill_build_line_starts
// ══════════════════════════════════════════════════════════════════════════
#[no_mangle]
pub unsafe extern "C" fn quill_build_line_starts(tp:*const u8,tl:i32,out:*mut i32,oc:i32)->i32{
    if tp.is_null()||out.is_null()||tl<0||oc<1{return -1;}
    let t=slice::from_raw_parts(tp,tl as usize); let cap=oc as usize;
    let mut cnt=0;
    if cnt<cap{ptr::write(out.add(cnt),0);cnt+=1;}
    for (i,&b) in t.iter().enumerate(){if b==b'\n'{if cnt<cap{ptr::write(out.add(cnt),(i+1) as i32);}cnt+=1;}}
    cnt as i32
}

// ══════════════════════════════════════════════════════════════════════════
// 4. quill_max_line_length
// ══════════════════════════════════════════════════════════════════════════
#[no_mangle]
pub unsafe extern "C" fn quill_max_line_length(lens:*const i32,n:i32)->i32{
    if lens.is_null()||n<=0{return -1;}
    slice::from_raw_parts(lens,n as usize).iter().copied().max().unwrap_or(0)
}

// ══════════════════════════════════════════════════════════════════════════
// 5. quill_bracket_match
//    Replaces BracketMatcher._findForward/_findBackward.
//    Old Dart: _inString = O(col) per character → O(lineLen * lineLen) worst case.
//    This: one-pass string-state tracking → O(lineLen) per line.
// ══════════════════════════════════════════════════════════════════════════
fn closer_for(c:u8)->u8{ match c{b'{'=> b'}',b'('=> b')',b'['=> b']',_=>0}}
fn opener_for(c:u8)->u8{ match c{b'}'=> b'{',b')'=>b'(',b']'=>b'[',_=>0}}
fn is_opener(c:u8)->bool{c==b'{' ||c==b'('||c==b'['}
fn is_closer(c:u8)->bool{c==b'}' ||c==b')'||c==b']'}

// One-pass string mask: bit i = 1 if position i is inside a string literal.
fn str_mask(l:&[u8])->[u64;4]{
    let mut m=[0u64;4]; let mut s1=false; let mut s2=false;
    for (i,&c) in l.iter().enumerate(){
        if i>=256{break;}
        if s1||s2{m[i/64]|=1<<(i%64);}
        let esc=i>0&&l[i-1]==b'\\';
        match c{
            b'\'' if !s2&&!esc=>s1=!s1,
            b'"' if !s1&&!esc=>s2=!s2,
            _=>{}
        }
    }
    m
}
#[inline(always)] fn in_str(m:&[u64;4],i:usize)->bool{if i>=256{false}else{(m[i/64]>>(i%64))&1==1}}

#[no_mangle]
pub unsafe extern "C" fn quill_bracket_match(
    lp:*const*const u8,ll:*const i32,lc:i32,
    cl:i32,cc:i32,out:*mut i32
)->i32{
    if lp.is_null()||ll.is_null()||out.is_null()||lc<=0||cl<0||cc<0{return -1;}
    let total=lc as usize; let cl=cl as usize; let cc=cc as usize;
    if cl>=total{return 0;}
    let gl=|li:usize|->&[u8]{
        let p=*lp.add(li); let l=*ll.add(li);
        if p.is_null()||l<0{&[]}else{slice::from_raw_parts(p,l as usize)}
    };
    let cline=gl(cl);
    let (sc,oc,fwd)=
        if cc<cline.len()&&is_opener(cline[cc]){(cc,cline[cc],true)}
        else if cc>0&&cc-1<cline.len()&&is_closer(cline[cc-1]){let c=cline[cc-1];(cc-1,opener_for(c),false)}
        else if cc<cline.len()&&is_closer(cline[cc]){let c=cline[cc];(cc,opener_for(c),false)}
        else{return 0;};
    let close=closer_for(oc); if close==0{return 0;}
    const MAX:usize=300;
    if fwd {
        let mut depth=0i32; let mut li=cl;
        while li<total&&li<=cl+MAX{
            let ln=gl(li); let m=str_mask(ln);
            let ci0=if li==cl{sc}else{0};
            let mut ci=ci0;
            while ci<ln.len(){
                if !in_str(&m,ci){
                    if ln[ci]==oc{depth+=1;}
                    else if ln[ci]==close{depth-=1;if depth==0{
                        ptr::write(out,cl as i32); ptr::write(out.add(1),sc as i32);
                        ptr::write(out.add(2),li as i32); ptr::write(out.add(3),ci as i32);
                        return 1;
                    }}
                }
                ci+=1;
            }
            li+=1;
        }
    } else {
        let mut depth=0i32; let mut li=cl as i64;
        while li>=0&&li>=cl as i64-MAX as i64{
            let ln=gl(li as usize); let m=str_mask(ln);
            let ce=if li as usize==cl{sc+1}else{ln.len()};
            let mut ci=ce;
            while ci>0{ci-=1;
                if !in_str(&m,ci){
                    if ln[ci]==close{depth+=1;}
                    else if ln[ci]==oc{depth-=1;if depth==0{
                        ptr::write(out,li as i32); ptr::write(out.add(1),ci as i32);
                        ptr::write(out.add(2),cl as i32); ptr::write(out.add(3),sc as i32);
                        return 1;
                    }}
                }
            }
            li-=1;
        }
    }
    0
}

// ══════════════════════════════════════════════════════════════════════════
// 6. quill_fulltext_join
//    Replaces Content.fullText StringBuffer loop (O(n) allocs in Dart).
//    Caller allocates buffer; returns bytes written or -1.
// ══════════════════════════════════════════════════════════════════════════
#[no_mangle]
pub unsafe extern "C" fn quill_fulltext_join(
    lp:*const*const u8,ll:*const i32,lc:i32,out:*mut u8,oc:i32
)->i32{
    if lp.is_null()||ll.is_null()||out.is_null()||lc<=0||oc<=0{return -1;}
    let n=lc as usize; let cap=oc as usize; let mut pos=0usize;
    for i in 0..n {
        let p=*lp.add(i); let l=*ll.add(i);
        if p.is_null()||l<0{continue;}
        let line=slice::from_raw_parts(p,l as usize);
        if pos+line.len()+1>cap{return -1;}
        ptr::copy_nonoverlapping(line.as_ptr(),out.add(pos),line.len());
        pos+=line.len();
        if i+1<n{*out.add(pos)=b'\n'; pos+=1;}
    }
    pos as i32
}

// ══════════════════════════════════════════════════════════════════════════
// 7. quill_tokenize_line
//    Regex-free per-line tokenizer. Used for incremental single-line edits
//    on the UI thread — avoids the isolate round-trip for simple keystrokes.
//    keyword table: [len_byte, word_bytes..., type_idx_byte, ...]
// ══════════════════════════════════════════════════════════════════════════
#[allow(dead_code)]
const TN:u32=0; const TKW:u32=1; const TCM:u32=2; const TST:u32=3;
const TNU:u32=4; const TOP:u32=5; const TID:u32=6; const TFN:u32=7;
const TTY:u32=8; const TAN:u32=9; const TPU:u32=19;

fn kw_lookup(word:&[u8],kw:&[u8])->u8{
    let mut i=0;
    while i<kw.len(){
        let wl=kw[i] as usize; i+=1;
        if i+wl+1>kw.len(){break;}
        if &kw[i..i+wl]==word{return kw[i+wl];}
        i+=wl+1;
    }
    0xFF
}

#[inline(always)]
fn emit_tok(out:&mut[u32],op:&mut usize,col:u32,t:u32){
    if *op+1<out.len(){out[*op]=col;out[*op+1]=t;*op+=2;}
}

#[no_mangle]
pub unsafe extern "C" fn quill_tokenize_line(
    lp:*const u8,ll:i32,kp:*const u8,kl:i32,out:*mut u32,oc:i32
)->i32{
    if lp.is_null()||out.is_null()||ll<0||oc<2{return -1;}
    let line=slice::from_raw_parts(lp,ll as usize);
    let kw=if kp.is_null()||kl<=0{&[]as &[u8]}else{slice::from_raw_parts(kp,kl as usize)};
    let os=slice::from_raw_parts_mut(out,(oc as usize)*2);
    let n=line.len(); let mut pos=0usize; let mut op=0usize;
    while pos<n {
        let c=line[pos];
        if c==b'/'&&pos+1<n&&line[pos+1]==b'/'{emit_tok(os,&mut op,pos as u32,TCM);break;}
        if c==b'/'&&pos+1<n&&line[pos+1]==b'*'{
            let s=pos; pos+=2;
            while pos+1<n&&!(line[pos]==b'*'&&line[pos+1]==b'/'){pos+=1;}
            pos=(pos+2).min(n);
            emit_tok(os,&mut op,s as u32,TCM); continue;
        }
        if c==b'@'{let s=pos;pos+=1;while pos<n&&is_word(line[pos]){pos+=1;}emit_tok(os,&mut op,s as u32,TAN);continue;}
        if c==b'"' ||c==b'\''{
            let d=c; let s=pos; pos+=1;
            while pos<n{if line[pos]==b'\\'{pos+=2;continue;}if line[pos]==d{pos+=1;break;}pos+=1;}
            emit_tok(os,&mut op,s as u32,TST); continue;
        }
        if is_digit(c)||(c==b'0'&&pos+1<n&&(line[pos+1]==b'x'||line[pos+1]==b'X')){
            let s=pos;
            if c==b'0'&&pos+1<n&&(line[pos+1]==b'x'||line[pos+1]==b'X'){
                pos+=2; while pos<n&&(line[pos].is_ascii_hexdigit()||line[pos]==b'_'){pos+=1;}
            } else {
                while pos<n&&(is_digit(line[pos])||line[pos]==b'.'||line[pos]==b'_'||line[pos]==b'e'||line[pos]==b'E'){pos+=1;}
            }
            emit_tok(os,&mut op,s as u32,TNU); continue;
        }
        if c.is_ascii_alphabetic()||c==b'_'{
            let s=pos; while pos<n&&is_word(line[pos]){pos+=1;}
            let word=&line[s..pos];
            let mut lk=pos; while lk<n&&(line[lk]==b' '||line[lk]==b'\t'){lk+=1;}
            let np=lk<n&&line[lk]==b'(';
            let kt=kw_lookup(word,kw);
            if kt!=0xFF{emit_tok(os,&mut op,s as u32,kt as u32);}
            else if is_upper(word[0]){emit_tok(os,&mut op,s as u32,TTY);}
            else if np{emit_tok(os,&mut op,s as u32,TFN);}
            else{emit_tok(os,&mut op,s as u32,TID);}
            continue;
        }
        if b"+-*/%&|^~<>!=?:".contains(&c){
            let s=pos; while pos<n&&b"+-*/%&|^~<>!=?:".contains(&line[pos]){pos+=1;}
            if op<2||os[op-1]!=TOP{emit_tok(os,&mut op,s as u32,TOP);}
            continue;
        }
        if b"(){}[];,.".contains(&c){
            if op<2||os[op-1]!=TPU{emit_tok(os,&mut op,pos as u32,TPU);}
            pos+=1; continue;
        }
        pos+=1;
    }
    (op/2) as i32
}

// ══════════════════════════════════════════════════════════════════════════
// 8. quill_symbol_scan
//    Replaces SymbolAnalyzer.extractSymbols Dart regex scan.
//    out: [line, col_start, col_end, kind, ...] kind: 0=class 1=mixin 2=ext 3=enum 4=func 5=var
// ══════════════════════════════════════════════════════════════════════════
#[no_mangle]
pub unsafe extern "C" fn quill_symbol_scan(
    lp:*const*const u8,ll:*const i32,lc:i32,out:*mut i32,oc:i32
)->i32{
    if lp.is_null()||ll.is_null()||out.is_null()||lc<=0||oc<4{return -1;}
    let n=lc as usize; let cap=(oc as usize)/4; let mut cnt=0;
    let class_kws:&[(&[u8],i32)]=&[
        (b"abstract class ",0),(b"base class ",0),(b"sealed class ",0),(b"class ",0),
        (b"mixin ",1),(b"extension ",2),(b"enum ",3),
    ];
    let ret_kws:&[&[u8]]=&[b"void ",b"int ",b"String ",b"bool ",b"double ",
        b"List ",b"Map ",b"Future ",b"Stream ",b"Widget ",b"Object "];
    let decl_kws:&[&[u8]]=&[b"final ",b"var ",b"late ",b"const ",b"static "];

    for li in 0..n {
        if cnt>=cap{break;}
        let p=*lp.add(li); let l=*ll.add(li);
        if p.is_null()||l<=0{continue;}
        let raw=slice::from_raw_parts(p,l as usize);
        let ind=skip_ws(raw,0); let line=&raw[ind..];
        if line.is_empty()||sw(line,b"//")||sw(line,b"/*"){continue;}
        let mut found=false;
        for &(kw,kind) in class_kws {
            if sw(line,kw) {
                let ns=kw.len();
                if ns<line.len()&&(line[ns].is_ascii_alphabetic()||line[ns]==b'_'){
                    let ne=word_end(line,ns);
                    if cnt<cap{
                        ptr::write(out.add(cnt*4),li as i32);
                        ptr::write(out.add(cnt*4+1),(ind+ns) as i32);
                        ptr::write(out.add(cnt*4+2),(ind+ne) as i32);
                        ptr::write(out.add(cnt*4+3),kind);
                        cnt+=1;
                    }
                }
                found=true; break;
            }
        }
        if !found {
            for &rk in ret_kws {
                if sw(line,rk){
                    let ar=skip_ws(line,rk.len());
                    if ar<line.len()&&(line[ar].is_ascii_alphabetic()||line[ar]==b'_'){
                        let ne=word_end(line,ar);
                        let an=skip_ws(line,ne);
                        if an<line.len()&&line[an]==b'(' {
                            if cnt<cap{
                                ptr::write(out.add(cnt*4),li as i32);
                                ptr::write(out.add(cnt*4+1),(ind+ar) as i32);
                                ptr::write(out.add(cnt*4+2),(ind+ne) as i32);
                                ptr::write(out.add(cnt*4+3),4i32);
                                cnt+=1;
                            }
                            found=true;
                        }
                    }
                    break;
                }
            }
        }
        if !found {
            for &dk in decl_kws {
                if sw(line,dk){
                    let mut i=dk.len();
                    while i<line.len()&&line[i]!=b'='&&line[i]!=b';'&&line[i]!=b'('{i+=1;}
                    while i>dk.len()&&(line[i-1]==b' '||line[i-1]==b'='||line[i-1]==b';'){ i-=1;}
                    let ne=i; while i>dk.len()&&is_word(line[i-1]){i-=1;}
                    let ns=i;
                    if ns<ne&&(line[ns].is_ascii_alphabetic()||line[ns]==b'_') {
                        if cnt<cap{
                            ptr::write(out.add(cnt*4),li as i32);
                            ptr::write(out.add(cnt*4+1),(ind+ns) as i32);
                            ptr::write(out.add(cnt*4+2),(ind+ne) as i32);
                            ptr::write(out.add(cnt*4+3),5i32);
                            cnt+=1;
                        }
                    }
                    break;
                }
            }
        }
    }
    cnt as i32
}


// ══════════════════════════════════════════════════════════════════════════
// 9. quill_has_structural_char
//    Returns 1 if the text contains { } ( ) or ends with :
//    Replaces Dart _hasStructuralChar — called on every keystroke.
// ══════════════════════════════════════════════════════════════════════════
#[no_mangle]
pub unsafe extern "C" fn quill_has_structural_char(p:*const u8,l:i32)->i32{
    if p.is_null()||l<=0{return 0;}
    let s=slice::from_raw_parts(p,l as usize);
    for &c in s { if c==b'{'||c==b'}'||c==b'('||c==b')'{return 1;} }
    // colon at end-of-line (Python/YAML/Dart label style)
    let mut e=s.len();
    while e>0&&(s[e-1]==b' '||s[e-1]==b'\t'){e-=1;}
    if e>0&&s[e-1]==b':'{return 1;}
    0
}

// ══════════════════════════════════════════════════════════════════════════
// 10. quill_strip_fold_opener
//     Strips trailing { ( : from a fold header line.
//     Replaces Dart _stripFoldOpener — called for every folded line in paint.
//     out: caller-provided buffer; returns bytes written or -1.
// ══════════════════════════════════════════════════════════════════════════
#[no_mangle]
pub unsafe extern "C" fn quill_strip_fold_opener(
    p:*const u8,l:i32,out:*mut u8,oc:i32
)->i32{
    if p.is_null()||out.is_null()||l<=0||oc<=0{return -1;}
    let src=slice::from_raw_parts(p,l as usize);
    let cap=oc as usize;
    let mut end=src.len();
    // strip trailing whitespace
    while end>0&&(src[end-1]==b' '||src[end-1]==b'\t'){end-=1;}
    if end==0{
        if cap>0{ptr::write(out,0);}return 0;
    }
    let last=src[end-1];
    if last==b'{'||last==b'('||last==b':' {
        end-=1;
        while end>0&&(src[end-1]==b' '||src[end-1]==b'\t'){end-=1;}
    }
    // cap at 50 bytes
    let n=end.min(50).min(cap);
    ptr::copy_nonoverlapping(src.as_ptr(),out,n);
    n as i32
}

// ══════════════════════════════════════════════════════════════════════════
// 11. quill_validate_blocks
//     Validates existing blocks after a structural edit — removes blocks
//     whose opener/closer lines no longer contain the expected chars.
//     Replaces Dart _validateBlocks — O(blocks * lineLen).
//
//     in_out: flat array of [start0,end0,indent0, start1,end1,indent1, ...]
//     Returns number of valid blocks kept (modifies array in-place).
// ══════════════════════════════════════════════════════════════════════════
#[inline(always)]
fn has_opener(l:&[u8])->bool{
    let mut s1=false; let mut s2=false;
    for (i,&c) in l.iter().enumerate(){
        let esc=i>0&&l[i-1]==b'\\';
        if !s1&&!s2{
            if c==b'/'&&i+1<l.len()&&l[i+1]==b'/'{break;}
            match c{
                b'\'' if !esc=>s1=true,
                b'"' if !esc=>s2=true,
                b'{'|b'('=>return true,
                b':'=>{
                    // colon at end of non-comment content
                    let mut e=l.len();
                    while e>0&&(l[e-1]==b' '||l[e-1]==b'\t'){e-=1;}
                    if i+1>=e{return true;}
                }
                _=>{}
            }
        } else {
            match (s1,s2){
                (true,_)=>if c==b'\''&&!esc{s1=false;}
                (_,true)=>if c==b'"'&&!esc{s2=false;}
                _=>{}
            }
        }
    }
    false
}

#[inline(always)]
fn first_nonws_char(l:&[u8])->u8{
    for &c in l{if c!=b' '&&c!=b'\t'{return c;}}
    0
}

#[no_mangle]
pub unsafe extern "C" fn quill_validate_blocks(
    lp:*const*const u8,ll:*const i32,lc:i32,
    in_out:*mut i32,block_count:i32
)->i32{
    if lp.is_null()||ll.is_null()||in_out.is_null()||lc<=0||block_count<=0{return 0;}
    let total=lc as usize; let bc=block_count as usize;
    let gl=|li:usize|->&[u8]{
        let p=*lp.add(li); let l=*ll.add(li);
        if p.is_null()||l<0{&[]}else{slice::from_raw_parts(p,l as usize)}
    };
    let mut kept=0usize;
    for i in 0..bc {
        let sl=*in_out.add(i*3)   as usize;
        let el=*in_out.add(i*3+1) as usize;
        let ind=*in_out.add(i*3+2);
        if sl>=total||el>=total||el<=sl{continue;}
        let sline=gl(sl); let eline=gl(el);
        if !has_opener(sline){continue;}
        // For brace blocks: closer must be } or ) as first non-whitespace
        let fc=first_nonws_char(eline);
        if fc!=b'}'&&fc!=b')'&&fc!=0{
            // Allow colon-style blocks (no closer char requirement)
            let mut has_colon=false;
            let mut e=sline.len();
            while e>0&&(sline[e-1]==b' '||sline[e-1]==b'\t'){e-=1;}
            if e>0&&sline[e-1]==b':'{has_colon=true;}
            if !has_colon{continue;}
        }
        if kept!=i {
            ptr::write(in_out.add(kept*3),   sl as i32);
            ptr::write(in_out.add(kept*3+1), el as i32);
            ptr::write(in_out.add(kept*3+2), ind);
        }
        kept+=1;
    }
    kept as i32
}

// ══════════════════════════════════════════════════════════════════════════
// 12. quill_indent_advance
//     Returns the indent advance for a line (used for auto-indent on Enter).
//     Returns 4 if line ends with { ( [, else 0.
//     Replaces Dart getIndentAdvance — trimRight + endsWith per keystroke.
// ══════════════════════════════════════════════════════════════════════════
#[no_mangle]
pub unsafe extern "C" fn quill_indent_advance(p:*const u8,l:i32)->i32{
    if p.is_null()||l<=0{return 0;}
    let s=slice::from_raw_parts(p,l as usize);
    let mut e=s.len();
    while e>0&&(s[e-1]==b' '||s[e-1]==b'\t'){e-=1;}
    if e==0{return 0;}
    match s[e-1]{b'{'|b'('|b'['=>4,_=>0}
}

// ══════════════════════════════════════════════════════════════════════════
// 13. quill_pos_to_offset / quill_offset_to_pos
//     O(line) offset conversion — replaces Dart positionToOffset/offsetToPosition.
//     Used by LSP, search, and range operations.
// ══════════════════════════════════════════════════════════════════════════
#[no_mangle]
pub unsafe extern "C" fn quill_pos_to_offset(
    ll:*const i32, lc:i32, line:i32, col:i32
)->i32{
    if ll.is_null()||lc<=0||line<0||col<0{return -1;}
    let n=lc as usize; let ln=line as usize;
    if ln>=n{return -1;}
    let lens=slice::from_raw_parts(ll,n);
    let mut off=0i32;
    for i in 0..ln{ off+=lens[i]+1; } // +1 for newline
    off+col
}

#[no_mangle]
pub unsafe extern "C" fn quill_offset_to_pos(
    ll:*const i32, lc:i32, offset:i32,
    out_line:*mut i32, out_col:*mut i32
)->i32{
    if ll.is_null()||out_line.is_null()||out_col.is_null()||lc<=0||offset<0{return -1;}
    let n=lc as usize;
    let lens=slice::from_raw_parts(ll,n);
    let mut rem=offset;
    for i in 0..n{
        let ll=lens[i];
        if rem<=ll{
            ptr::write(out_line,i as i32);
            ptr::write(out_col,rem);
            return 0;
        }
        rem-=ll+1;
    }
    // past end — clamp to last position
    let last=(n-1) as i32;
    ptr::write(out_line,last);
    ptr::write(out_col,lens[n-1]);
    0
}