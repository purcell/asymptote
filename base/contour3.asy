int ncell=10;

import graph_settings;
import light;

real eps=10000*realEpsilon;

private struct weighted
{
  triple normal;
  real ratio;
  int kpa0,kpa1,kpa2;
  int kpb0,kpb1,kpb2;
  triple v;
}

private struct bucket
{
  triple v;
  triple val;
  int count;
  pair z;
}

struct vertex
{
  pair z;
  triple normal;
}

// A group of 3 or 4 points.
private struct object
{
  bool active;
  weighted[] pts;
}

// Return contour vertices for a 3D data array, using a pyramid mesh
// f,mp:      three-dimensional arrays of real data values
// a,b:       'bottom' and 'top' vertices of contour domain
vertex[][] contour3(real[][][] f, real[][][] mp=new real[][][] ,
                    triple a, triple b,
                    projection P=currentprojection)
{
  int nx=f.length-1;
  if(nx == 0)
    abort("array f must have length >= 2");
  int ny=f[0].length-1;
  if(ny == 0)
    abort("array f[0] must have length >= 2");
  int nz=f[0][0].length-1;
  if(nz == 0)
    abort("array f[0][0] must have length >= 2");
 
  // check if boundaries are good
  if(b.x <= a.x || b.y <= a.y) {
    abort("bad contour domain: all coordinates of b-a must be positive.");
  }
 
  bool midpoints=mp.length > 0;
  if(!midpoints) mp=new real[2nx+1][2ny+1][2nz+1];

  bucket[][][][] kps=new bucket[2nx+1][2ny+1][2nz+1][];
  for(int i=0; i < 2nx+1; ++i)
    for(int j=0; j < 2ny+1; ++j)
      for(int k=0; k < 2nz+1; ++k)
        kps[i][j][k]=new bucket[];

  for(int i=0; i <= nx; ++i)
    for(int j=0; j <= ny; ++j)
      for(int k=0; k <= nz; ++k)
        mp[2i][2j][2k]=f[i][j][k];   

  object[] objects;

  real dx=(b.x-a.x)/nx;
  real dy=(b.y-a.y)/ny;
  real dz=(b.z-a.z)/nz;
  
  // go over region a rectangle at a time
  for(int i=0; i < nx; ++i) {
    real x=a.x+i*dx;
    real[][] fi=f[i];
    real[][] fi1=f[i+1];
    int i2=2i;
    int i2p1=i2+1;
    int i2p2=i2+2;
    for(int j=0; j < ny; ++j) {
      real y=a.y+j*dy;
      real[] fij=fi[j];
      real[] fi1j=fi1[j];
      real[] fij1=fi[j+1];
      real[] fi1j1=fi1[j+1];
      int j2=2j;
      int j2p1=j2+1;
      int j2p2=j2+2;
 
      for(int k=0; k < nz; ++k) {
        real z=a.z+k*dz;

        // vertex values
        real vdat0=fij[k];
        real vdat1=fij[k+1];
        real vdat2=fij1[k];
        real vdat3=fij1[k+1];
        real vdat4=fi1j[k];
        real vdat5=fi1j[k+1];
        real vdat6=fi1j1[k];
        real vdat7=fi1j1[k+1];

        // define points
        triple p000=(x,y,z);
        triple p001=(x,y,z+dz);
        triple p010=(x,y+dy,z);
        triple p011=(x,y+dy,z+dz);
        triple p100=(x+dx,y,z);
        triple p101=(x+dx,y,z+dz);
        triple p110=(x+dx,y+dy,z);
        triple p111=(x+dx,y+dy,z+dz);
        triple m0=0.25*(p000+p010+p110+p100);
        triple m1=0.25*(p010+p110+p111+p011);
        triple m2=0.25*(p110+p100+p101+p111);
        triple m3=0.25*(p100+p000+p001+p101);
        triple m4=0.25*(p000+p010+p011+p001);
        triple m5=0.25*(p001+p011+p111+p101);
        triple mc=0.5*(m0+m5);                   

        // optimization: we make sure we don't work with empty rectangles
        int countm=0;
        int countz=0;
        int countp=0;
        
        void check(real vdat) {
          if(vdat < -eps) ++countm;
          else {
            if(vdat <= eps) ++countz; 
            else ++countp;
          }
        }
        
        check(vdat0);
        check(vdat1);
        check(vdat2);
        check(vdat3);
        check(vdat4);
        check(vdat5);
        check(vdat6);
        check(vdat7);

        if(countm == 8 || countp == 8 || 
           ((countm == 7 || countp == 7) && countz == 1)) continue;

        int k2=2k;
        int k2p1=k2+1;
        int k2p2=k2+2;
 
        // Evaluate midpoints of cube sides.
        // Then evaluate midpoint of cube.
        real vdat8=midpoints ? mp[i2p1][j2p1][k2] :
          0.25*(vdat0+vdat2+vdat6+vdat4);
        real vdat9=midpoints ? mp[i2p1][j2p2][k2p1] : 
          0.25*(vdat2+vdat6+vdat7+vdat3);
        real vdat10=midpoints ? mp[i2p2][j2p1][k2p1] : 
          0.25*(vdat7+vdat6+vdat4+vdat5);
        real vdat11=midpoints ? mp[i2p1][j2][k2p1] : 
          0.25*(vdat0+vdat4+vdat5+vdat1);
        real vdat12=midpoints ? mp[i2][j2p1][k2p1] : 
          0.25*(vdat0+vdat2+vdat3+vdat1);
        real vdat13=midpoints ? mp[i2p1][j2p1][k2p2] : 
          0.25*(vdat1+vdat3+vdat7+vdat5);
        real vdat14=midpoints ? mp[i2p1][j2p1][k2p1] : 
          0.125*(vdat0+vdat1+vdat2+vdat3+vdat4+vdat5+vdat6+vdat7);
      
        // Go through the 24 pyramids, 4 for each side.
        
        void addval(int kp0, int kp1, int kp2, triple add, triple v) {
          bucket[] cur=kps[kp0][kp1][kp2];
          for(int q=0; q < cur.length; ++q) {
            if(length(cur[q].v-v) < eps) {
              cur[q].val += add;
              ++cur[q].count;
	      return;
            }
          }
          bucket newbuck;
          newbuck.v=v;
          newbuck.z=project(v,P);
          newbuck.val=add;
          newbuck.count=1;
          cur.push(newbuck);
        }

        void accrue(weighted w) {
          triple val1=w.normal*w.ratio;
          triple val2=w.normal*(1-w.ratio);
          addval(w.kpa0,w.kpa1,w.kpa2,val1,w.v);
          addval(w.kpb0,w.kpb1,w.kpb2,val2,w.v);
        }

	triple dir=P.camera-P.target;

        void addnormals(weighted[] pts) {
          triple vec2=pts[1].v-pts[0].v;
          triple vec1=pts[0].v-pts[2].v;
	  triple vec0=-vec2-vec1;
	  vec2=unit(vec2);
	  vec1=unit(vec1);
	  vec0=unit(vec0);
          triple normal=cross(vec2,vec1);
	  normal *= sgn(dot(normal,dir));
	  real angle0=acos(-dot(vec1,vec2));
	  real angle1=acos(-dot(vec2,vec0));
          pts[0].normal=normal*angle0;
          pts[1].normal=normal*angle1;
          pts[2].normal=normal*(pi-angle0-angle1);
        }

        void addobj(object obj) {
          if(!obj.active) return;

          if(obj.pts.length == 4) {
            weighted[] points=obj.pts;
            object obj1;
            object obj2;
            obj1.active=true; 
            obj2.active=true;
            obj1.pts=new weighted[] {points[0],points[1],points[2]};
            obj2.pts=new weighted[] {points[1],points[2],points[3]};
            addobj(obj1);
            addobj(obj2);
          } else {
            addnormals(obj.pts);
            for(int q=0; q < obj.pts.length; ++q)
              accrue(obj.pts[q]);
            objects.push(obj);
          }
        }

        weighted setupweighted(triple va, triple vb, real da, real db, 
                               int[] kpa, int[] kpb) {
          weighted w;
          real ratio=abs(da/(db-da));
          w.v=interp(va,vb,ratio);
          w.ratio=ratio;
          w.kpa0=i2+kpa[0];
          w.kpa1=j2+kpa[1];
          w.kpa2=k2+kpa[2];
          w.kpb0=i2+kpb[0];
          w.kpb1=j2+kpb[1];
          w.kpb2=k2+kpb[2];

          return w;
        }

        weighted setupweighted(triple v, int[] kp) {
          weighted w;
          w.v=v;
          w.ratio=0.5;
          w.kpa0=w.kpb0=i2+kp[0];
          w.kpa1=w.kpb1=j2+kp[1];
          w.kpa2=w.kpb2=k2+kp[2];

          return w;
        }

        // Checks if a pyramid contains a contour object.
        object checkpyr(triple v0, triple v1, triple v2, triple v3,
                        real d0, real d1, real d2, real d3,
                        int[] c0, int[] c1, int[] c2, int[] c3) {
          object obj;
          real a0=abs(d0);
          real a1=abs(d1);
          real a2=abs(d2);
          real a3=abs(d3);

          bool b0=a0 < eps;
          bool b1=a1 < eps;
          bool b2=a2 < eps;
          bool b3=a3 < eps;

          weighted[] pts;

          if(b0) pts.push(setupweighted(v0,c0));
          if(b1) pts.push(setupweighted(v1,c1));
          if(b2) pts.push(setupweighted(v2,c2));
          if(b3) pts.push(setupweighted(v3,c3));

          if(!b0 && !b1 && abs(d0+d1)+eps < a0+a1)
            pts.push(setupweighted(v0,v1,d0,d1,c0,c1));
          if(!b0 && !b2 && abs(d0+d2)+eps < a0+a2)
            pts.push(setupweighted(v0,v2,d0,d2,c0,c2));
          if(!b0 && !b3 && abs(d0+d3)+eps < a0+a3)
            pts.push(setupweighted(v0,v3,d0,d3,c0,c3));
          if(!b1 && !b2 && abs(d1+d2)+eps < a1+a2)
            pts.push(setupweighted(v1,v2,d1,d2,c1,c2));
          if(!b1 && !b3 && abs(d1+d3)+eps < a1+a3)
            pts.push(setupweighted(v1,v3,d1,d3,c1,c3));
          if(!b2 && !b3 && abs(d2+d3)+eps < a2+a3)
            pts.push(setupweighted(v2,v3,d2,d3,c2,c3));

          int s=pts.length;
          //There are three or four points.
          if(s > 2) {
            obj.active=true;
            obj.pts=pts;
          }
          else obj.active=false;

          return obj;
        }

        void check4pyr(triple v0, triple v1, triple v2, triple v3,
                       triple v4, triple v5,
                       real d0, real d1, real d2, real d3, real d4, real d5,
                       int[] c0, int[] c1, int[] c2, int[] c3, int[] c4,
                       int[] c5) {
          addobj(checkpyr(v5,v4,v0,v1,d5,d4,d0,d1,c5,c4,c0,c1));
          addobj(checkpyr(v5,v4,v1,v2,d5,d4,d1,d2,c5,c4,c1,c2));
          addobj(checkpyr(v5,v4,v2,v3,d5,d4,d2,d3,c5,c4,c2,c3));
          addobj(checkpyr(v5,v4,v3,v0,d5,d4,d3,d0,c5,c4,c3,c0));
        }

        static int[] pp000={0,0,0};
        static int[] pp001={0,0,2};
        static int[] pp010={0,2,0};
        static int[] pp011={0,2,2};
        static int[] pp100={2,0,0};
        static int[] pp101={2,0,2};
        static int[] pp110={2,2,0};
        static int[] pp111={2,2,2};
        static int[] pm0={1,1,0};
        static int[] pm1={1,2,1};
        static int[] pm2={2,1,1};
        static int[] pm3={1,0,1};
        static int[] pm4={0,1,1};
        static int[] pm5={1,1,2};
        static int[] pmc={1,1,1};
 
        check4pyr(p000,p010,p110,p100,mc,m0,
                  vdat0,vdat2,vdat6,vdat4,vdat14,vdat8,
                  pp000,pp010,pp110,pp100,pmc,pm0);
        check4pyr(p010,p110,p111,p011,mc,m1,
                  vdat2,vdat6,vdat7,vdat3,vdat14,vdat9,
                  pp010,pp110,pp111,pp011,pmc,pm1);
        check4pyr(p110,p100,p101,p111,mc,m2,
                  vdat6,vdat4,vdat5,vdat7,vdat14,vdat10,
                  pp110,pp100,pp101,pp111,pmc,pm2);
        check4pyr(p100,p000,p001,p101,mc,m3,
                  vdat4,vdat0,vdat1,vdat5,vdat14,vdat11,
                  pp100,pp000,pp001,pp101,pmc,pm3);
        check4pyr(p000,p010,p011,p001,mc,m4,
                  vdat0,vdat2,vdat3,vdat1,vdat14,vdat12,
                  pp000,pp010,pp011,pp001,pmc,pm4);
        check4pyr(p001,p011,p111,p101,mc,m5,
                  vdat1,vdat3,vdat7,vdat5,vdat14,vdat13,
                  pp001,pp011,pp111,pp101,pmc,pm5);
      }
    }
  }

  vertex preparevertex(weighted w) {
    vertex ret;
    triple normal=O;
    bool first=true;
    bucket[] kp1=kps[w.kpa0][w.kpa1][w.kpa2];
    bucket[] kp2=kps[w.kpb0][w.kpb1][w.kpb2];
    bool notfound1=true;
    bool notfound2=true;
    int count=0;
    int stop=max(kp1.length,kp2.length);
    for(int r=0; r < stop; ++r) {
      if(notfound1) {
        if(length(w.v-kp1[r].v) < eps) {
          if(first) {
            ret.z=kp1[r].z;
            first=false;
          }
          normal += kp1[r].val;
          count += kp1[r].count;
          notfound1=false;
        }
      }
      if(notfound2) {
        if(length(w.v-kp2[r].v) < eps) {
          if(first) {
            ret.z=kp2[r].z;
            first=false;
          }
          normal += kp2[r].val;
          count += kp2[r].count;
          notfound2=false;
        }
      }
    }
    ret.normal=normal*2/count;
    return ret;
  }
  
  // Prepare return value.
  vertex[][] g;
  
  for(int q=0; q < objects.length; ++q) {
    object p=objects[q];
    g.push(new vertex[] {preparevertex(p.pts[0]),preparevertex(p.pts[1]),
          preparevertex(p.pts[2])});
  }
  return g;
}

// Return contour vertices for a 3D data array, using a pyramid mesh
// f:         Function from R3 to R.
// a,b:       'bottom' and 'top' vertices of contour domain
// nx,ny,nz   subdivisions on x, y and z axes
vertex[][] contour3(real f(real, real, real), triple a, triple b,
                    int nx=ncell, int ny=nx, int nz=nx,
                    projection P=currentprojection)
{
  // evaluate function at points and midpoints
  real[][][] dat=new real[nx+1][ny+1][nz+1];
  real[][][] midpoint=new real[2nx+2][2ny+2][2nz+1];

  for(int i=0; i <= nx; ++i) {
    real x=interp(a.x,b.x,i/nx);
    real x2=interp(a.x,b.x,(i+0.5)/nx);
    real[][] dati=dat[i];
    real[][] midpointi2=midpoint[2i];
    real[][] midpointi2p1=midpoint[2i+1];
    for(int j=0; j <= ny; ++j) {
      real y=interp(a.y,b.y,j/ny);
      real y2=interp(a.y,b.y,(j+0.5)/ny);
      real datij[]=dati[j];
      real[] midpointi2p1j2=midpointi2p1[2j];
      real[] midpointi2p1j2p1=midpointi2p1[2j+1];
      real[] midpointi2j2p1=midpointi2[2j+1];
      for(int k=0; k <= nz; ++k) {
        real z=interp(a.z,b.z,k/nz);
        real z2=interp(a.z,b.z,(k+0.5)/nz);
        datij[k]=f(x,y,z);
        if(i == nx || j == ny || k == nz) continue;
        int k2p1=2k+1;
        midpointi2p1j2p1[2k]=f(x2,y2,z); 
        midpointi2p1j2p1[k2p1]=f(x2,y2,z2);
        midpointi2p1j2[k2p1]=f(x2,y,z2);
        midpointi2j2p1[k2p1]=f(x,y2,z2);
        if(i == 0) midpoint[2nx][2j+1][k2p1]=f(b.x,y2,z2);
        if(j == 0) midpointi2p1[2ny][k2p1]=f(x2,b.y,z2);
        if(k == 0) midpointi2p1j2p1[2nz]=f(x2,y2,b.z);
      }
    }
  }
  return contour3(dat,midpoint,a,b,P);
}

// Return contour guides for a 3D data array, using a pyramid mesh
void draw(picture pic=currentpicture, vertex[][] g, pen p=lightgray,
          light light=currentlight)
{
  begingroup(pic);
  int[] edges={0,0,0};
  for(int i=0; i < g.length; ++i) {
    vertex[] cur=g[i];
    pen pen0=light.intensity(cur[0].normal)*p;
    pen pen1=light.intensity(cur[1].normal)*p;
    pen pen2=light.intensity(cur[2].normal)*p;
    gouraudshade(pic,cur[0].z--cur[1].z--cur[2].z--cycle,
		 new pen[] {pen0,pen1,pen2}, edges);
  }
  endgroup(pic);
}