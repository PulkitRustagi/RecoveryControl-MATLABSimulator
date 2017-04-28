function qout = quatmultiply_JPL( p, q )
    qout = [p(1) -p(2) -p(3) -p(4);
            p(2) p(1) p(4) -p(3);
            p(3) -p(4) p(1) p(2);
            p(4) p(3) -p(2) p(1)] * [q(1);q(2);q(3);q(4)];
end