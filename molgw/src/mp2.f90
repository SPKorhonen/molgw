!=========================================================================
#include "macros.h"
!=========================================================================
subroutine mp2_energy(nspin,basis,occupation,c_matrix,energy,emp2)
 use m_definitions
 use m_mpi
 use m_basis_set
 use m_eri
 implicit none

 integer,intent(in)         :: nspin
 type(basis_set),intent(in) :: basis
 real(dp),intent(in)        :: occupation(basis%nbf,nspin),c_matrix(basis%nbf,basis%nbf,nspin),energy(basis%nbf,nspin)
 real(dp),intent(out)       :: emp2
!=====
 integer                    :: aorbital,borbital,iorbital,jorbital
 integer                    :: ibf,jbf,abf,bbf,ispin,jspin
 real(dp)                   :: energy_denom
 real(dp)                   :: tmp_xaxb(basis%nbf,basis%nbf)
 real(dp)                   :: tmp_iaxb(basis%nbf),tmp_xaib(basis%nbf)
 real(dp)                   :: tmp_iajb,tmp_jaib
 real(dp)                   :: contrib1,contrib2
 real(dp)                   :: fact,spin_fact
 real(dp),allocatable       :: tmp_xaxx(:,:,:)
!=====

 emp2 = 0.0_dp
 contrib1 = 0.0_dp
 contrib2 = 0.0_dp

 spin_fact = REAL(-nspin+3,dp)


 allocate(tmp_xaxx(basis%nbf,basis%nbf,basis%nbf))

 do ispin=1,nspin

   do aorbital=1,basis%nbf
     if(occupation(aorbital,ispin)>spin_fact-completely_empty) cycle

     WRITE_MASTER(*,'(i4,2x,i4,a,i4)') ispin,aorbital,' / ',basis%nbf

     tmp_xaxx(:,:,:) = 0.0_dp
!$OMP PARALLEL DEFAULT(SHARED)
!$OMP DO REDUCTION(+:tmp_xaxx)
     do bbf=1,basis%nbf
       do jbf=1,basis%nbf
!FIXME         if( negligible_basispair(jbf,bbf) ) cycle
         do abf=1,basis%nbf
           do ibf=1,basis%nbf
!FIXME             if( negligible_basispair(ibf,abf) ) cycle
             tmp_xaxx(ibf,jbf,bbf) = tmp_xaxx(ibf,jbf,bbf) &
&               + c_matrix(abf,aorbital,ispin) * eri(ibf,abf,jbf,bbf)
           enddo
         enddo
       enddo
     enddo
!$OMP END DO
!$OMP END PARALLEL

     do jspin=1,nspin
       do borbital=1,basis%nbf
         if(occupation(borbital,jspin)>spin_fact-completely_empty) cycle
       
         tmp_xaxb(:,:) = 0.0_dp
!$OMP PARALLEL DEFAULT(SHARED)
!$OMP DO REDUCTION(+:tmp_xaxb)
         do bbf=1,basis%nbf
           do jbf=1,basis%nbf
             do ibf=1,basis%nbf
               tmp_xaxb(ibf,jbf) = tmp_xaxb(ibf,jbf) + c_matrix(bbf,borbital,jspin) * tmp_xaxx(ibf,jbf,bbf)
             enddo
           enddo
         enddo
!$OMP END DO
!$OMP END PARALLEL

         do iorbital=1,basis%nbf
           if(occupation(iorbital,ispin)<completely_empty) cycle

           tmp_iaxb(:) = 0.0_dp
           tmp_xaib(:) = 0.0_dp
           do jbf=1,basis%nbf
             do ibf=1,basis%nbf
               tmp_iaxb(jbf) = tmp_iaxb(jbf) + c_matrix(ibf,iorbital,ispin) * tmp_xaxb(ibf,jbf)
             enddo
           enddo
           do jbf=1,basis%nbf
             do ibf=1,basis%nbf
               tmp_xaib(jbf) = tmp_xaib(jbf) + c_matrix(ibf,iorbital,ispin) * tmp_xaxb(jbf,ibf)
             enddo
           enddo

           do jorbital=1,basis%nbf
             if(occupation(jorbital,jspin)<completely_empty) cycle

             fact =  occupation(iorbital,ispin) * ( 1.0_dp - occupation(aorbital,ispin) ) &
&                   *occupation(jorbital,jspin) * ( 1.0_dp - occupation(borbital,jspin) )

             energy_denom = energy(iorbital,ispin) + energy(jorbital,jspin) &
&                                    - energy(aorbital,ispin) - energy(borbital,jspin)
             ! Avoid the zero denominators
             if( ABS(energy_denom) < 1.d-18) then
               WRITE_MASTER(*,*) 'you skipped something'
               cycle
             endif
             energy_denom =  fact / energy_denom 

             tmp_iajb = SUM( tmp_iaxb(:) * c_matrix(:,jorbital,jspin) )
             tmp_jaib = SUM( tmp_xaib(:) * c_matrix(:,jorbital,jspin) )

             contrib1 = contrib1 + 0.5_dp * energy_denom * tmp_iajb**2 

             if(ispin==jspin) contrib2 = contrib2 - 0.5_dp * energy_denom * tmp_iajb*tmp_jaib / spin_fact


           enddo
         enddo
       enddo
     enddo !jspin

   enddo ! aorbital

 enddo !ispin

 deallocate(tmp_xaxx)


 emp2 = contrib1 + contrib2
 WRITE_MASTER(*,'(/,a)')       ' MP2 contributions'
 WRITE_MASTER(*,'(a,f14.8)')   ' 2-ring diagram  :',contrib1
 WRITE_MASTER(*,'(a,f14.8)')   ' SOX diagram     :',contrib2
 WRITE_MASTER(*,'(a,f14.8,/)') ' MP2 correlation :',emp2


end subroutine mp2_energy


!==================================================================
subroutine mp2_energy_fast(nspin,basis,occupation,c_matrix,energy,emp2)
 use m_definitions
 use m_mpi
 use m_basis_set
 use m_eri
 implicit none

 integer,intent(in)         :: nspin
 type(basis_set),intent(in) :: basis
 real(dp),intent(in)        :: occupation(basis%nbf,nspin),c_matrix(basis%nbf,basis%nbf,nspin),energy(basis%nbf,nspin)
 real(dp),intent(out)       :: emp2
!=====
 integer                    :: aorbital,borbital,iorbital,jorbital
 integer                    :: ibf,jbf,abf,bbf,iaspin,jbspin
 real(dp)                   :: energy_denom
 real(dp)                   :: tmp_ixjx(basis%nbf,basis%nbf)
 real(dp)                   :: tmp_iajx(basis%nbf),tmp_ixja(basis%nbf)
 real(dp)                   :: tmp_iajb,tmp_ibja
 real(dp)                   :: contrib1,contrib2
 real(dp)                   :: fact,spin_fact
 real(dp),allocatable       :: tmp_ixxx(:,:,:)
 integer                    :: nocc,ncore
 logical                    :: file_exists
!=====

 WRITE_MASTER(*,*) 'starting the MP2 calculation'
 !
 ! Deal with frozen core initialization
 inquire(file='manual_frozencore',exist=file_exists)
 if(file_exists) then
   !
   ! ncore_G and ncore_W contain the highest core state to be discarded
   open(13,file='manual_frozencore')
   read(13,*) ncore
   close(13)
   ncore = MAX(ncore,0)
   WRITE_MASTER(msg,'(a,i4,2x,i4)') 'frozen core approximation for MP2 switched on up to state = ',ncore
   call issue_warning(msg)
 else
   ncore = 0
 endif


 emp2 = 0.0_dp
 contrib1 = 0.0_dp
 contrib2 = 0.0_dp

 spin_fact = REAL(-nspin+3,dp)


 allocate(tmp_ixxx(basis%nbf,basis%nbf,basis%nbf))

 do iaspin=1,nspin
   !
   ! First, set up the list of occupied states
   nocc = 0
   do iorbital=ncore+1,basis%nbf
     if( occupation(iorbital,iaspin) < completely_empty ) cycle
     nocc = nocc + 1
   enddo
   call init_fast_distribution(nocc)

   do iorbital=ncore+1,basis%nbf
     if( occupation(iorbital,iaspin) < completely_empty ) cycle
     if( .NOT. is_my_fast_task(iorbital-ncore) ) cycle

     WRITE_MASTER(*,'(i4,2x,i4,a,i4)') iaspin,iorbital-ncore,' / ',nocc

     tmp_ixxx(:,:,:) = 0.0_dp
!$OMP PARALLEL DEFAULT(SHARED)
!$OMP DO REDUCTION(+:tmp_ixxx)
     do bbf=1,basis%nbf
       do jbf=1,basis%nbf
         if( negligible_basispair(jbf,bbf) ) cycle
         do abf=1,basis%nbf
           do ibf=1,basis%nbf
             if( negligible_basispair(ibf,abf) ) cycle
             tmp_ixxx(abf,jbf,bbf) = tmp_ixxx(abf,jbf,bbf) &
&               + c_matrix(ibf,iorbital,iaspin) * eri(ibf,abf,jbf,bbf)
           enddo
         enddo
       enddo
     enddo
!$OMP END DO
!$OMP END PARALLEL

     do jbspin=1,nspin
       do jorbital=ncore+1,basis%nbf
         if( occupation(jorbital,jbspin) < completely_empty ) cycle
       
         tmp_ixjx(:,:) = 0.0_dp
!$OMP PARALLEL DEFAULT(SHARED)
!$OMP DO REDUCTION(+:tmp_ixjx)
         do bbf=1,basis%nbf
           do jbf=1,basis%nbf
             do abf=1,basis%nbf
               tmp_ixjx(abf,bbf) = tmp_ixjx(abf,bbf) + c_matrix(jbf,jorbital,jbspin) * tmp_ixxx(abf,jbf,bbf)
             enddo
           enddo
         enddo
!$OMP END DO
!$OMP END PARALLEL

         do aorbital=1,basis%nbf
           if( occupation(aorbital,iaspin) > spin_fact - completely_empty ) cycle

           tmp_iajx(:) = 0.0_dp
           do bbf=1,basis%nbf
             do abf=1,basis%nbf
               tmp_iajx(bbf) = tmp_iajx(bbf) + c_matrix(abf,aorbital,iaspin) * tmp_ixjx(abf,bbf)
             enddo
           enddo

           if(iaspin==jbspin) then 
             tmp_ixja(:) = 0.0_dp
             do abf=1,basis%nbf
               do bbf=1,basis%nbf
                 tmp_ixja(bbf) = tmp_ixja(bbf) + c_matrix(abf,aorbital,iaspin) * tmp_ixjx(bbf,abf)
               enddo
             enddo
           endif

           do borbital=1,basis%nbf
             if( occupation(borbital,jbspin) > spin_fact - completely_empty ) cycle

             fact =  occupation(iorbital,iaspin) * ( 1.0_dp - occupation(aorbital,iaspin) ) &
&                   *occupation(jorbital,jbspin) * ( 1.0_dp - occupation(borbital,jbspin) )

             energy_denom = energy(iorbital,iaspin) + energy(jorbital,jbspin) &
&                                    - energy(aorbital,iaspin) - energy(borbital,jbspin)
             ! Avoid the zero denominators
             if( ABS(energy_denom) < 1.d-18) then
               WRITE_MASTER(*,*) 'you skipped something'
               cycle
             endif

             energy_denom =  fact / energy_denom 

             tmp_iajb = SUM( tmp_iajx(:) * c_matrix(:,borbital,jbspin) )

             contrib1 = contrib1 + 0.5_dp * energy_denom * tmp_iajb**2 

             if(iaspin==jbspin) then
               tmp_ibja = SUM( tmp_ixja(:) * c_matrix(:,borbital,jbspin) )
               contrib2 = contrib2 - 0.5_dp * energy_denom * tmp_iajb*tmp_ibja / spin_fact
             endif

           enddo
         enddo
       enddo
     enddo !jbspin

   enddo ! iorbital

   call destroy_fast_distribution()
 enddo !iaspin

 call xsum(contrib1)
 call xsum(contrib2)

 deallocate(tmp_ixxx)


 emp2 = contrib1 + contrib2
 WRITE_MASTER(*,'(/,a)')       ' MP2 contributions'
 WRITE_MASTER(*,'(a,f14.8)')   ' 2-ring diagram  :',contrib1
 WRITE_MASTER(*,'(a,f14.8)')   ' SOX diagram     :',contrib2
 WRITE_MASTER(*,'(a,f14.8,/)') ' MP2 correlation :',emp2


end subroutine mp2_energy_fast

!==================================================================
subroutine full_ci_2electrons_spin(print_wfn,spinstate,basis,h_1e,c_matrix,nuc_nuc)
 use m_definitions
 use m_mpi
 use m_tools
 use m_basis_set
 use m_eri
! use wavefunction_object
! use basis
 implicit none
!
 integer,parameter :: cip=dp
 integer,parameter :: nx=4000
!
 logical,intent(in)         :: print_wfn
 integer,intent(in)         :: spinstate
 type(basis_set),intent(in) :: basis
 real(dp),intent(in)        :: h_1e(basis%nbf,basis%nbf),c_matrix(basis%nbf,basis%nbf)
 real(dp),intent(in)        :: nuc_nuc
!=====
 integer,parameter    :: neig=6
 integer,parameter    :: nblock=2
 integer,parameter    :: ncycle=12
 integer              :: ieig,jeig,keig,neigc,icycle,iblock,jblock
 real(dp),allocatable :: bb(:,:),qq(:,:),atilde(:,:),ab(:,:)
 real(dp),allocatable :: bb_s(:,:),atilde_s(:,:),ab_s(:,:)
 real(dp),allocatable :: lambda(:),alphavec(:,:)
 real(dp) :: h_1e_hf(basis%nbf,basis%nbf)
 integer :: nconf,iconf,jconf,kconf
 integer :: ibf,jbf,kbf,lbf
 integer :: istate,jstate,kstate,lstate
 integer :: istate1,istate2,jstate1,jstate2,ispin1,ispin2,jspin1,jspin2
 real(cip),allocatable :: hamiltonian(:,:)
 real(cip),allocatable :: energy(:),eigenvector(:,:)
 real(cip),allocatable :: test1(:),test2(:),test3(:),hphi(:),gr1(:),gr2(:)
 real(cip) :: delta,eigen,hessian,norm_gr1
 integer :: iline,ix
 real(dp) :: rhor(nx),rhor_hf(nx),rr(3)
 real(dp) :: rhor_t(nx)
 real(dp) :: eval_wfn(basis%nbf)
#if defined LOW_MEMORY2 || defined LOW_MEMORY3
 real(dp) :: eri_hf_i(basis%nbf,basis%nbf,basis%nbf,1)
#else
 real(dp) :: eri_hf(basis%nbf,basis%nbf,basis%nbf,basis%nbf)
#endif
 integer,parameter :: ny=nx,nz=nx
 integer :: iy,iz
 real(dp) :: xxx(nx),y(ny),z(nz)
 real(dp) :: wx(nx),wy(ny),wz(nz)
 real(dp) :: norm
 character(len=100)      :: title

 integer :: ibf_cart,li,ni,ni_cart,i_cart
 real(dp),allocatable :: basis_function_r_cart(:)
 real(dp) :: basis_function_r(basis%nbf)

!=====
 WRITE_MASTER(*,*) 
 WRITE_MASTER(*,*) 'Enter full CI subroutine'
 WRITE_MASTER(*,*) 

 WRITE_MASTER(*,*) 'obtain the one-electron Hamiltonian in the HF basis'
 h_1e_hf(:,:) = 0.0_dp
 do jstate=1,basis%nbf
   do istate=1,basis%nbf
     do jbf=1,basis%nbf
       do ibf=1,basis%nbf
         h_1e_hf(istate,jstate) = h_1e_hf(istate,jstate) + h_1e(ibf,jbf) * c_matrix(ibf,istate) * c_matrix(jbf,jstate)
       enddo
     enddo
   enddo
 enddo

#ifndef LOW_MEMORY2 
#ifndef LOW_MEMORY3
 call transform_eri_basis_fast(basis%nbf,1,c_matrix,eri_hf)
#endif
#endif

 select case(spinstate)
 case(0)
   WRITE_MASTER(*,*) 'calculate spin singlet state'
 case(1)
   WRITE_MASTER(*,*) 'calculate spin triplet state'
 case default
   stop'BUG: spin state not possible'
 end select

 nconf = ( 2*basis%nbf * (2*basis%nbf -1) ) / 2
 WRITE_MASTER(*,*)
 WRITE_MASTER(*,*) 'CI matrix lower than',nconf,' x ',nconf
 allocate(hamiltonian(nconf,nconf))
 hamiltonian(:,:) = 0.0_dp
 do iconf=1,nconf
   hamiltonian(iconf,iconf) = nuc_nuc
 enddo

 iconf=0
 do istate1=1,basis%nbf
#if defined LOW_MEMORY2 || defined LOW_MEMORY3
     call transform_eri_basis_lowmem(1,c_matrix,istate1,1,eri_hf_i)
#endif
   do ispin1=1,2

     do istate2=istate1,basis%nbf
       do ispin2=1,2
         if(istate1==istate2 .AND. (ispin2==1 .OR. ispin1==2) ) cycle
         !
         ! S^2 selection
!         if(ABS(ispin1-ispin2)==spinstate) cycle
         !
         ! for two electrons, the two electron wavefunction is even in space
         ! the two one-particle wavefunctions have then to have the parity 
!TODO         if(.NOT.symmetry(istate1,istate2)) cycle
         iconf=iconf+1

         jconf=0
         do jstate1=1,basis%nbf
           do jspin1=1,2
             do jstate2=jstate1,basis%nbf
               do jspin2=1,2
                 if(jstate1==jstate2 .AND. (jspin2==1 .OR. jspin1==2) ) cycle
                 !
                 ! S^2 selection
!                 if(ABS(jspin1-jspin2)==spinstate) cycle
                 !
                 ! for two electrons, the two electron wavefunction is even in space
                 ! the two one-particle wavefunctions have then to have the parity 
!TODO                 if(.NOT.symmetry(jstate1,jstate2)) cycle
                 jconf=jconf+1

!         WRITE_MASTER(*,'(10(i4,x))') jconf,jstate1,jspin1,jstate2,jspin2

                 if( istate2==jstate2 .AND. ispin2==jspin2 .AND. ispin1==jspin1 ) hamiltonian(iconf,jconf) = hamiltonian(iconf,jconf) + h_1e_hf(istate1,jstate1)
                 if( istate1==jstate1 .AND. ispin1==jspin1 .AND. ispin2==jspin2 ) hamiltonian(iconf,jconf) = hamiltonian(iconf,jconf) + h_1e_hf(istate2,jstate2)
                 if( istate2==jstate1 .AND. ispin2==jspin1 .AND. ispin1==jspin2 ) hamiltonian(iconf,jconf) = hamiltonian(iconf,jconf) - h_1e_hf(istate1,jstate2)
                 if( istate1==jstate2 .AND. ispin1==jspin2 .AND. ispin2==jspin1 ) hamiltonian(iconf,jconf) = hamiltonian(iconf,jconf) - h_1e_hf(istate2,jstate1)


                 !
                 ! Not so painful implementation of the determinant rules as shown in
                 ! p. 70 of "Modern Quantum Chemistry" by A. Szabo and N. S. Ostlung

#if defined LOW_MEMORY2 || defined LOW_MEMORY3
                 if( ispin1==jspin1 .AND. ispin2==jspin2 ) hamiltonian(iconf,jconf) =  hamiltonian(iconf,jconf) + eri_hf_i(jstate1,istate2,jstate2,1)
                 if( ispin1==jspin2 .AND. ispin2==jspin1 ) hamiltonian(iconf,jconf) =  hamiltonian(iconf,jconf) - eri_hf_i(jstate2,istate2,jstate1,1)
#else
                 if( ispin1==jspin1 .AND. ispin2==jspin2 ) hamiltonian(iconf,jconf) =  hamiltonian(iconf,jconf) + eri_hf(istate1,jstate1,istate2,jstate2)
                 if( ispin1==jspin2 .AND. ispin2==jspin1 ) hamiltonian(iconf,jconf) =  hamiltonian(iconf,jconf) - eri_hf(istate1,jstate2,istate2,jstate1)
#endif



               enddo
             enddo
           enddo
         enddo

       enddo
     enddo
   enddo
 enddo

 ! Adjust the real size of the CI hamiltonian
 nconf=iconf
 WRITE_MASTER(*,*)
 WRITE_MASTER(*,*) 'CI matrix finally is',nconf,' x ',nconf

 WRITE_MASTER(*,*) 'Single determinant ground state energy [Ha]',hamiltonian(1,1)
! WRITE_MASTER(*,*) '=========== H_1e ============== '
! do istate=1,basis%nbf
!   WRITE_MASTER(*,'(i4,2x,20(x,f12.6))') iconf,h_1e_hf(istate,1:basis%nbf)
! enddo
!#ifndef LOW_MEMORY2
! WRITE_MASTER(*,*) '=========== J_ij ============== '
! do istate=1,basis%nbf
!   WRITE_MASTER(*,'(i4,2x,20(x,f12.6))') iconf,(eri_hf(istate,istate,jstate,jstate),jstate=1,basis%nbf)
! enddo
! WRITE_MASTER(*,*) '=========== K_ij ============== '
! do istate=1,basis%nbf
!   WRITE_MASTER(*,'(i4,2x,20(x,f12.6))') iconf,(eri_hf(istate,jstate,jstate,istate),jstate=1,basis%nbf)
! enddo
!#endif
! WRITE_MASTER(*,*) '=========== full H ============== '
! do iconf=1,nconf
!   WRITE_MASTER(*,'(i4,2x,20(x,f12.6))') iconf,hamiltonian(iconf,1:nconf)
! enddo

 allocate(energy(nconf),eigenvector(nconf,nconf))
 !
 ! resize the matrices
 eigenvector(:,:) = hamiltonian(1:nconf,1:nconf)
 deallocate(hamiltonian)
 allocate(hamiltonian(nconf,nconf))
 hamiltonian(:,:) = eigenvector(:,:)

 if(nconf>2000) then ! iterative partial diago or full diago
   ! home made steepest descent algo
   WRITE_MASTER(*,*)
   WRITE_MASTER(*,*) 'hamiltonian too big to be diagonalized'
   WRITE_MASTER(*,*) 'Slow steepest descent algorithm'
   WRITE_MASTER(*,*) 'home cooked'
   allocate(test1(nconf),test2(nconf),hphi(nconf),gr1(nconf),gr2(nconf))
   test1(:) = 0.001
   test1(1) = 1. 
   test1(:) = test1(:) / SQRT( SUM( test1(:)**2 ) )
   delta = 0.10
  
   do iline=1,500
  
     hphi = matmul(eigenvector,test1)
     eigen = dot_product(test1,hphi)
     gr1(:) = 2. * ( hphi(:) - eigen * test1(:) )
     norm_gr1 = SQRT(dot_product(gr1,gr1))
!     WRITE_MASTER(*,*) 'x1',norm_gr1
  
!     WRITE_MASTER(*,*) 'guessed delta',delta
     test2(:) = test1(:) - delta * gr1(:) / norm_gr1
     test2(:) = test2(:) / SQRT( SUM( test2(:)**2 ) )
  
     hphi = matmul(eigenvector,test2)
     eigen = dot_product(test2,hphi)
     gr2(:) = 2. * ( hphi(:) - eigen * test2(:) )
!     WRITE_MASTER(*,*) 'x2',dot_product(gr2,gr1)/norm_gr1
     hessian = dot_product(gr1,gr2-gr1) / ( delta * norm_gr1 )
     delta = -norm_gr1 / hessian
!     WRITE_MASTER(*,*) 'optimal delta',delta
     test2(:) = test1(:) - delta * gr1(:) / norm_gr1
     test2(:) = test2(:) / SQRT( SUM( test2(:)**2 ) )
  
     if(modulo(iline,20)==0) then
       WRITE_MASTER(*,*) 'diff',iline,eigen,SUM(ABS(test2(:)-test1(:)))/DBLE(nconf)
     endif
!     WRITE_MASTER(*,*) '==================='
     if( SUM(ABS(test2(:)-test1(:)))/DBLE(nconf) < 1.e-12_dp ) exit
     test1(:) = test2(:)
  
   enddo

   eigenvector(:,1) =test1(:)
   energy(1) = eigen
   
   deallocate(test1,test2,hphi,gr1,gr2)

 else if( .TRUE. ) then
   WRITE_MASTER(*,*) 
   WRITE_MASTER(*,*) 'Davidson diago'
   WRITE_MASTER(*,*) 'trial vectors'

   allocate(bb_s(nconf,neig+ncycle*nblock))
   allocate(qq(nconf,nblock))
   !
   ! Initialize with stupid coefficients
   bb_s(:,1:neig)=0.001_dp
   do ieig=1,neig
     bb_s(ieig,ieig) = 1.0_dp
     ! orthogonalize to previous vectors
     do keig=1,ieig-1
       bb_s(:,ieig) = bb_s(:,ieig) - bb_s(:,keig) * DOT_PRODUCT( bb_s(:,ieig) , bb_s(:,keig) )
     enddo
     ! normalize
     bb_s(:,ieig) = bb_s(:,ieig) / NORM2( bb_s(:,ieig) )
   enddo

   do jeig=1,neig,nblock

     do icycle=1,ncycle

       neigc = neig + ( icycle - 1 ) * nblock

       allocate(bb(nconf,neigc))
       bb(:,:) = bb_s(:,1:neigc)

       allocate(ab(nconf,neigc),atilde(neigc,neigc))

       ab(:,:) = MATMUL( hamiltonian(:,:) , bb(:,:) )

       atilde(:,:) = MATMUL( TRANSPOSE(bb(:,:)) , ab(:,:) )

       allocate(lambda(neigc),alphavec(neigc,neigc))
       call diagonalize(neigc,atilde,lambda,alphavec)

       do iblock=1,nblock
         qq(:,iblock) = MATMUL( ab ,  alphavec(:,jeig+iblock-1) ) &
                 - lambda(jeig+iblock-1) * MATMUL ( bb , alphavec(:,jeig+iblock-1) )

         WRITE_MASTER(*,'(a,i4,x,i4,x,e12.4)') ' Residual norm for eigenvalue,cycle',&
                       icycle,jeig+iblock-1,NORM2(qq(:,iblock))

         do iconf=1,nconf
           qq(iconf,iblock) = qq(iconf,iblock) / ( lambda(jeig+iblock-1) - hamiltonian(iconf,iconf) )
         enddo
         ! orthogonalize
         do ieig=1,neigc
           qq(:,iblock) = qq(:,iblock) - bb(:,ieig) * DOT_PRODUCT( bb(:,ieig) , qq(:,iblock) )
         enddo
         do jblock=1,iblock-1
           qq(:,iblock) = qq(:,iblock) - qq(:,jblock) * DOT_PRODUCT( qq(:,jblock) , qq(:,iblock) )
         enddo
         qq(:,iblock) = qq(:,iblock) / NORM2( qq(:,iblock) )

       enddo

       if(icycle<ncycle) then
         do iblock=1,nblock
           bb_s(:,neigc+iblock) = qq(:,iblock)
         enddo
       else
         do iblock=1,nblock
           do ieig=jeig,neig
             bb_s(:,ieig+iblock-1) = MATMUL( bb , alphavec(:,ieig+iblock-1) )
           enddo
           energy(jeig+iblock-1) = lambda(jeig+iblock-1)
         enddo
       endif
       deallocate(ab,atilde,lambda,alphavec,bb)

     enddo ! icycle
     WRITE_MASTER(*,*) 
   enddo ! jeig

   WRITE_MASTER(*,*) 'diago DONE'
   WRITE_MASTER(*,*) energy(1:min(neig,nconf))
   eigenvector(:,1:neig) = bb_s(:,1:neig)

   deallocate(bb_s,qq)

  else
   ! full LAPACK diago
   WRITE_MASTER(*,*) 'starting the diago'
   call diagonalize(nconf,hamiltonian,energy,eigenvector)
   WRITE_MASTER(*,*) 'diago DONE'
   WRITE_MASTER(*,*) energy(1:min(neig,nconf))

 endif

 WRITE_MASTER(*,*)
 WRITE_MASTER(*,*) 'normalization',SUM(eigenvector(:,1)**2)
 WRITE_MASTER(*,'(i4,2x,20(x,f7.4))') 1,eigenvector(1:min(20,nconf),1)
 WRITE_MASTER(*,*)
 WRITE_MASTER(*,'(a30,2x,f14.8)') 'CI ground-state energy [Ha]:',energy(1)
 WRITE_MASTER(*,'(a30,2x,f14.8)') 'correlation energy [Ha]:',energy(1)-hamiltonian(1,1)
 WRITE_MASTER(*,*)
  
 deallocate(hamiltonian)


 !
 ! Plot the ground state density if requested
 !
 if( print_wfn ) then
   WRITE_MASTER(*,*)
   WRITE_MASTER(*,*) 'calculate the density'
  
  
   rhor(:)=0.0_dp
   rhor_hf(:)=0.0_dp
   do ix=1,nx
     rr(1)= ( DBLE(ix-1)/DBLE(nx-1) - 0.5 ) * 10.0
     rr(2)= 0.0
     rr(3)= 0.0
  

     !
     ! First precalculate all the needed basis function evaluations at point rr
     !
     ibf_cart = 1
     ibf      = 1
     do while(ibf_cart<=basis%nbf_cart)
       li      = basis%bf(ibf_cart)%am
       ni_cart = number_basis_function_am(CARTESIAN,li)
       ni      = number_basis_function_am(basis%gaussian_type,li)
  
       allocate(basis_function_r_cart(ni_cart))
  
       do i_cart=1,ni_cart
         basis_function_r_cart(i_cart) = eval_basis_function(basis%bf(ibf_cart+i_cart-1),rr)
       enddo
       basis_function_r(ibf:ibf+ni-1) = MATMUL(  basis_function_r_cart(:) , cart_to_pure(li)%matrix(:,:) )
       deallocate(basis_function_r_cart)
  
       ibf      = ibf      + ni
       ibf_cart = ibf_cart + ni_cart
     enddo
     !
     ! Precalculation done!
     !

  
     eval_wfn(:)=0.0_dp
     do istate=1,basis%nbf
       do ibf=1,basis%nbf
         eval_wfn(istate) = eval_wfn(istate) + c_matrix(ibf,istate) * basis_function_r(ibf)
       enddo
     enddo
    
    do kconf=1,1
    
     iconf=0
     do istate1=1,basis%nbf
       do ispin1=1,2
         do istate2=istate1,basis%nbf
           do ispin2=1,2
             if(istate1==istate2 .AND. (ispin2==1 .OR. ispin1==2) ) cycle
  !           !
  !           ! S^2 selection
  !           if(ABS(ispin1-ispin2)==spinstate) cycle
             !
             ! for two electrons, the two electron wavefunction is even in space
             ! the two one-particle wavefunctions have then to have the parity 
    !TODO         if(.NOT.symmetry(istate1,istate2)) cycle
             iconf=iconf+1
    
             jconf=0
             do jstate1=1,basis%nbf
               do jspin1=1,2
                 do jstate2=jstate1,basis%nbf
                   do jspin2=1,2
                     if(jstate1==jstate2 .AND. (jspin2==1 .OR. jspin1==2) ) cycle
    !                 !
    !                 ! S^2 selection
    !                 if(ABS(jspin1-jspin2)==spinstate) cycle
                     !
                     ! for two electrons, the two electron wavefunction is even in space
                     ! the two one-particle wavefunctions have then to have the parity 
    !TODO                 if(.NOT.symmetry(jstate1,jstate2)) cycle
                     jconf=jconf+1
    
    
                       if( istate2==jstate2 .AND. ispin2==jspin2 .AND. ispin1==jspin1 ) then
                         rhor(ix) = rhor(ix)  &
                          + eigenvector(iconf,kconf) * eigenvector(jconf,kconf) &
                           * eval_wfn(istate1) * eval_wfn(jstate1) 
                       endif
                       if( istate1==jstate1 .AND. ispin1==jspin1 .AND. ispin2==jspin2 ) then 
                         rhor(ix) = rhor(ix)  &
                          + eigenvector(iconf,kconf) * eigenvector(jconf,kconf) &
                           * eval_wfn(istate2) * eval_wfn(jstate2) 
                       endif
                       if( istate2==jstate1 .AND. ispin2==jspin1 .AND. ispin1==jspin2 ) then
                         rhor(ix) = rhor(ix)  &
                          - eigenvector(iconf,kconf) * eigenvector(jconf,kconf) &
                           * eval_wfn(istate1) * eval_wfn(jstate2)
                       endif
                       if( istate1==jstate2 .AND. ispin1==jspin2 .AND. ispin2==jspin1 ) then
                         rhor(ix) = rhor(ix)  &
                          - eigenvector(iconf,kconf) * eigenvector(jconf,kconf) &
                           * eval_wfn(istate2) * eval_wfn(jstate1)
                       endif
  
                       !
                       ! HARTREE-FOCK PART
                       if( iconf==kconf .AND. jconf==kconf ) then
                         if( istate2==jstate2 .AND. ispin2==jspin2 .AND. ispin1==jspin1 ) then
                           rhor_hf(ix) = rhor_hf(ix)  &
                            + eval_wfn(istate1) * eval_wfn(jstate1) 
                         endif
                         if( istate1==jstate1 .AND. ispin1==jspin1 .AND. ispin2==jspin2 ) then 
                           rhor_hf(ix) = rhor_hf(ix)  &
                            + eval_wfn(istate2) * eval_wfn(jstate2) 
                         endif
                         if( istate2==jstate1 .AND. ispin2==jspin1 .AND. ispin1==jspin2 ) then
                           rhor_hf(ix) = rhor_hf(ix)  &
                            - eval_wfn(istate1) * eval_wfn(jstate2)
                         endif
                         if( istate1==jstate2 .AND. ispin1==jspin2 .AND. ispin2==jspin1 ) then
                           rhor_hf(ix) = rhor_hf(ix)  &
                            - eval_wfn(istate2) * eval_wfn(jstate1)
                         endif
                       endif
    
    
    
                   enddo
                 enddo
               enddo
             enddo
    
           enddo
         enddo
       enddo
     enddo
  
     enddo  !kconf
  
   enddo !ix
   rhor(:)    = rhor   (:) * 0.5_dp  ! divide by two to compare with phi^star * phi which is normalized to unity
   rhor_hf(:) = rhor_hf(:) * 0.5_dp  ! divide by two to compare with phi^star * phi which is normalized to unity
  
  ! WRITE_MASTER(*,*) 'NORM',norm / DBLE(nx*ny*nz)
  ! WRITE_MASTER(*,*) 'norm',SUM(rhor(:)*wx(:))
  
  ! rhor_t(:)=0.0_dp
  ! do ix=1,nx
  ! do iy=1,ny
  ! do iz=1,nz
  !   rr(1)= x(ix)
  !   rr(2)= y(iy)
  !   rr(3)= z(iz)
  !   rhor_t(ix)=rhor_t(ix)+ eval_basis_function(basis%bf(1),rr)**2 * wy(iy) * wz(iz)
  ! enddo !iz
  ! enddo !iy
  ! enddo !ix
  ! WRITE_MASTER(*,*) 'norm',SUM(rhor_t(:)*wx(:))
  ! do ix=1,nx
  !   rr(1)= x(ix)
  !   WRITE_MASTER(11,'(5(e12.6,2x))') rr(1),rhor_t(ix)
  ! enddo
  
   do ix=1,nx
  !   rr(1)= x(ix)
     rr(1)= (DBLE(ix-1)/DBLE(nx-1)-0.5)*10.00
     rr(2)= 0.0
     rr(3)= 0.0
     WRITE_MASTER(10,'(5(e14.6,2x))') rr(1),rhor(ix),rhor_hf(ix)
   enddo

 endif

 ! finalize the CI calculation
 deallocate(energy,eigenvector)


end subroutine full_ci_2electrons_spin
