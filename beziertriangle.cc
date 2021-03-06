/*****
 * drawbeziertriangle.cc
 *
 * Stores a Bezier triangle that has been added to a picture.
 *****/

#include "drawsurface.h"

namespace camp {

static const double pixel=0.5; // Adaptive rendering constant.

extern const double Fuzz;
extern const double Fuzz2;

inline triple maxabs(triple u, triple v)
{
  return triple(max(fabs(u.getx()),fabs(v.getx())),
                max(fabs(u.gety()),fabs(v.gety())),
                max(fabs(u.getz()),fabs(v.getz())));
}

inline triple displacement1(const triple& z0, const triple& c0,
                            const triple& c1, const triple& z1)
{
  // z0-z1 is computed twice. This is unnecessary, although perhaps not a big
  // deal and way easier to understand in this case.
  return maxabs(displacement(c0,z0,z1),displacement(c1,z0,z1));
}

// return the perpendicular displacement of a point z from the plane
// through u with unit normal n.
inline triple displacement2(const triple& z, const triple& u, const triple& n)
{
  triple Z=z-u;
  return n != triple(0,0,0) ? dot(Z,n)*n : Z;
}
  
triple displacement(const triple *controls)
{
  triple d=drawElement::zero;

  triple z0=controls[0];
  triple z1=controls[6];
  triple z2=controls[9];

  // Optimize straight & planar cases.

  //for(size_t i=1; i < 10; ++i)
  // The last three lines compute how straight the edges are. This should be a
  // sufficient test for the boundry points, so only the central point is
  // tested for deviance from the main triangle.
  d=maxabs(d,displacement2(controls[4],z0,unit(cross(z1-z0,z2-z0))));

  d=maxabs(d,displacement1(z0,controls[1],controls[3],z1));
  d=maxabs(d,displacement1(z0,controls[2],controls[5],z2));
  d=maxabs(d,displacement1(z1,controls[7],controls[8],z2));

  // TODO: calculate displacement d from interior
  // Or simply assume a nondegenerate Jacobian.

  return d;
}

// Returns one-third of the first derivative of the Bezier curve defined by
// a,b,c,d at 0.
inline triple bezierP(triple a, triple b) {
  return b-a;
}

// Returns one-sixth of the second derivative of the Bezier curve defined
// by a,b,c,d at 0. 
inline triple bezierPP(triple a, triple b, triple c) {
  return a+c-2.0*b;
}

// Returns one-third of the third derivative of the Bezier curve defined by
// a,b,c,d.
inline triple bezierPPP(triple a, triple b, triple c, triple d) {
  return d-a+3.0*(b-c);
}

struct Render
{
  std::vector<GLfloat> buffer;
  std::vector<GLint> indices;
  triple u,v,w;
  GLuint nvertices;
  double cx,cy,cz;
  double epsilon;
  double res;
  bool billboard;
  
  void init(bool havebillboard, const triple& center) {
    const size_t nbuffer=10000;
    buffer.reserve(nbuffer);
    indices.reserve(nbuffer);
    nvertices=0;
    
    billboard=havebillboard;
    if(billboard) {
      cx=center.getx();
      cy=center.gety();
      cz=center.getz();

      gl::projection P=gl::camera(false);
      w=unit(P.camera-P.target);
      v=unit(perp(P.up,w));
      u=cross(v,w);
    }
  }
    
  void clear() {
    buffer.clear();
    indices.clear();
  }
  
// Store the vertex v and its normal vector n in the buffer.
  GLuint vertex(const triple& V, const triple& n) {
    if(billboard) {
      double x=V.getx()-cx;
      double y=V.gety()-cy;
      double z=V.getz()-cz;
      buffer.push_back(cx+u.getx()*x+v.getx()*y+w.getx()*z);
      buffer.push_back(cy+u.gety()*x+v.gety()*y+w.gety()*z);
      buffer.push_back(cz+u.getz()*x+v.getz()*y+w.getz()*z);
    } else {
      buffer.push_back(V.getx());
      buffer.push_back(V.gety());
      buffer.push_back(V.getz());
    }
    
    buffer.push_back(n.getx());
    buffer.push_back(n.gety());
    buffer.push_back(n.getz());
    return nvertices++;
  }
  
  
  triple normal0(triple left3, triple left2, triple left1, triple middle,
                 triple right1, triple right2, triple right3) {
    //cout << "normal0 called." << endl;
    // Lots of repetition here.
    // TODO: Check if lp,rp,lpp,rpp should be manually inlined (i.e., is the
    // third order normal usually computed when normal0() is called?).
    triple lp=bezierP(middle,left1);
    triple rp=bezierP(middle,right1);
    triple lpp=bezierPP(middle,left1,left2);
    triple rpp=bezierPP(middle,right1,right2);
    triple n1=cross(rpp,lp)+cross(rp,lpp);
    if(abs2(n1) > epsilon) {
      return unit(n1);
    } else {
      triple lppp=bezierPPP(middle,left1,left2,left3);
      triple rppp=bezierPPP(middle,right1,right2,right3);
      triple n2= 9.0*cross(rpp,lpp)+
        3.0*(cross(rp,lppp)+cross(rppp,lp)+
             cross(rppp,lpp)+cross(rpp,lppp))+
        cross(rppp,lppp);
      return unit(n2);
    }
  }

  triple normal(triple left3, triple left2, triple left1, triple middle,
                triple right1, triple right2, triple right3) {
    triple bu=right1-middle;
    triple bv=left1-middle;
    triple n=triple(bu.gety()*bv.getz()-bu.getz()*bv.gety(),
                    bu.getz()*bv.getx()-bu.getx()*bv.getz(),
                    bu.getx()*bv.gety()-bu.gety()*bv.getx());
    return abs2(n) > epsilon ? unit(n) :
      normal0(left3,left2,left1,middle,right1,right2,right3);
  }

// Pi is the full precision value indexed by Ii.
// The 'flati' are flatness flags for each boundary.
  void render(const triple *p, int n,
              GLuint I0, GLuint I1, GLuint I2,
              triple P0, triple P1, triple P2,
              bool flat1, bool flat2, bool flat3)
  {
    // Uses a uniform partition
    // p points to an array of 10 triples.
    // Draw a Bezier triangle.
    // p is the set of control points for the Bezier triangle
    // n is the maximum number of iterations to compute
    triple d=displacement(p);

    // This involves fewer triangle computations at the end (since if the
    // surface is sufficiently flat, it just draws the sufficiently flat
    // triangle, rather than trying to properly utilize the already
    // computed values. 

    if(n == 0 || length(d) < res) { // If triangle is flat...
      GLuint pp[]={I0,I1,I2};

      mesh(p,pp);
    } else { // Triangle is not flat

      /*    Naming Convention:
       *
       *                            030
       *                           /\
       *                          /  \
       *                         /    \
       *                        /      \
       *                       /   up   \
       *                      /          \
       *                     /            \
       *                    /              \
       *               pp2 /________________\ pp3
       *                  /\               / \
       *                 /  \             /   \
       *                /    \           /     \
       *               /      \  center /       \
       *              /        \       /         \
       *             /          \     /           \
       *            /    left    \   /    right    \
       *           /              \ /               \
       *          /________________V_________________\
       *       003                 pp1                 300
       */

      // Subdivide triangle
      triple l003=p[0];
      triple p102=p[1];
      triple p012=p[2];
      triple p201=p[3];
      triple p111=p[4];
      triple p021=p[5];
      triple r300=p[6];
      triple p210=p[7];
      triple p120=p[8];
      triple u030=p[9];

      triple u021=0.5*(u030+p021);
      triple u120=0.5*(u030+p120);

      triple p033=0.5*(p021+p012);
      triple p231=0.5*(p120+p111);
      triple p330=0.5*(p120+p210);

      triple p123=0.5*(p012+p111);

      triple l012=0.5*(p012+l003);
      triple p312=0.5*(p111+p201);
      triple r210=0.5*(p210+r300);

      triple l102=0.5*(l003+p102);
      triple p303=0.5*(p102+p201);
      triple r201=0.5*(p201+r300);

      triple u012=0.5*(u021+p033);
      triple u210=0.5*(u120+p330);
      triple l021=0.5*(p033+l012);
      triple p4xx=0.5*p231+0.25*(p111+p102);
      triple r120=0.5*(p330+r210);
      triple px4x=0.5*p123+0.25*(p111+p210);
      triple pxx4=0.25*(p021+p111)+0.5*p312;
      triple l201=0.5*(l102+p303);
      triple r102=0.5*(p303+r201);

      triple l210=0.5*(px4x+l201); // =c120
      triple r012=0.5*(px4x+r102); // =c021
      triple l300=0.5*(l201+r102); // =r003=c030

      triple r021=0.5*(pxx4+r120); // =c012
      triple u201=0.5*(u210+pxx4); // =c102
      triple r030=0.5*(u210+r120); // =u300=c003

      triple u102=0.5*(u012+p4xx); // =c201
      triple l120=0.5*(l021+p4xx); // =c210
      triple l030=0.5*(u012+l021); // =u003=c300

      triple l111=0.5*(p123+l102);
      triple r111=0.5*(p312+r210);
      triple u111=0.5*(u021+p231);
      triple c111=0.25*(p033+p330+p303+p111);

      //  For each edge of the triangle
      //    * Check for flatness
      //    * Store points in the GLU array accordingly

      // A kludge to remove subdivision cracks, only applied the first time
      // an edge is found to be flat before the rest of the sub-patch is.
      const double epsilon=0.1*res;
      GLuint a1,a2,a3;
      triple pp1,pp2,pp3;

      if(flat1)
        pp1=0.5*(P1+P0);
      else {
        if((flat1=length(displacement1(l003,p102,p201,r300)) < res))
          pp1=0.5*(P1+P0)+epsilon*unit(l300-u030);
        else
          pp1=l300;
      }

      if(flat2)
        pp2=0.5*(P2+P0);
      else {
        if((flat2=length(displacement1(l003,p012,p021,u030)) < res))
          pp2=0.5*(P2+P0)+epsilon*unit(l030-r300);
        else pp2=l030;
      }

      if(flat3)
        pp3=0.5*(P2+P1);
      else {
        if((flat3=length(displacement1(r300,p210,p120,u030)) < res))
          pp3=0.5*(P2+P1)+epsilon*unit(r030-l003);
        else pp3=r030;
      }

      a1=vertex(pp1,normal(l030,l120,l210,l300,r012,r021,r030));
      a2=vertex(pp2,normal(r030,u201,u102,l030,l120,l210,l300));
      a3=vertex(pp3,normal(l300,r012,r021,r030,u201,u102,l030));

      triple l[]={l003,l102,l012,l201,l111,l021,l300,l210,l120,l030}; // left
      triple r[]={l300,r102,r012,r201,r111,r021,r300,r210,r120,r030}; // right
      triple u[]={l030,u102,u012,u201,u111,u021,r030,u210,u120,u030}; // up
      triple c[]={r030,u201,r021,u102,c111,r012,l030,l120,l210,l300}; // center

      --n;
      render(l,n,I0,a1,a2,P0, pp1,pp2,flat1,flat2,false);
      render(r,n,a1,I1,a3,pp1,P1, pp3,flat1,false,flat3);
      render(u,n,a2,a3,I2,pp2,pp3,P2, false,flat2,flat3);
      render(c,n,a3,a2,a1,pp3,pp2,pp1,false,false,false);
    }
  }

// n is the maximum depth
  void render(const triple *p, double res, int n=8) {
    this->res=res;

    triple po=p[0];
    double epsilon=0;
    for(int i=1; i < 10; ++i)
      epsilon=max(epsilon,abs2(p[i]-po));
  
    epsilon *= Fuzz2;
  
    GLuint p0=vertex(p[0],normal(p[9],p[5],p[2],p[0],p[1],p[3],p[6]));
    GLuint p1=vertex(p[6],normal(p[0],p[1],p[3],p[6],p[7],p[8],p[9]));
    GLuint p2=vertex(p[9],normal(p[6],p[7],p[8],p[9],p[5],p[2],p[0]));

    if(n > 0) {
      render(p,n,p0,p1,p2,p[0],p[6],p[9],false,false,false);
    } else {
      GLuint I[]={p0,p1,p2};
      mesh(p,I);
    }
    
    size_t stride=6*sizeof(GL_FLOAT);

    glEnableClientState(GL_NORMAL_ARRAY);
    glEnableClientState(GL_VERTEX_ARRAY);
    glVertexPointer(3,GL_FLOAT,stride,&buffer[0]);
    glNormalPointer(GL_FLOAT,stride,&buffer[3]);
    glDrawElements(GL_TRIANGLES,indices.size(),GL_UNSIGNED_INT,
                   &indices[0]);
    glDisableClientState(GL_VERTEX_ARRAY);
    glDisableClientState(GL_NORMAL_ARRAY);
  }

  void mesh(const triple *p, const GLuint *I)
  {
    // Draw the frame of the control points of a cubic Bezier mesh
    GLuint I0=I[0];
    GLuint I1=I[1];
    GLuint I2=I[2];

    indices.push_back(I0);
    indices.push_back(I1);
    indices.push_back(I2);
  }
};

Render R;

void bezierTriangle(const triple *g, double Size2, triple Size3,
                    bool havebillboard, triple center)
{
  R.init(havebillboard,center);
  R.render(g,pixel*length(Size3)/fabs(Size2));
  R.clear();
}

} //namespace camp
